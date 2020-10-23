require "net/ping"
require "rbvmomi"

class Support
  class GuestCustomizationError < RuntimeError; end
  class GuestCustomizationOptionsError < RuntimeError; end

  module GuestCustomization
    DEFAULT_LINUX_TIMEZONE = "Etc/UTC".freeze
    DEFAULT_WINDOWS_ORG = "TestKitchen".freeze
    DEFAULT_WINDOWS_TIMEZONE = 0x80000050 # Etc/UTC
    DEFAULT_TIMEOUT_TASK = 600
    DEFAULT_TIMEOUT_IP = 60

    # Generic Volume License Keys for temporary Windows Server setup.
    #
    # @see https://docs.microsoft.com/en-us/windows-server/get-started/kmsclientkeys
    WINDOWS_KMS_KEYS = {
      "Microsoft Windows Server 2019 (64-bit)" => "N69G4-B89J2-4G8F4-WWYCC-J464C",
      "Microsoft Windows Server 2016 (64-bit)" => "WC2BQ-8NRM3-FDDYY-2BFGV-KHKQY",
      "Microsoft Windows Server 2012R2 (64-bit)" => "D2N9P-3P6X9-2R39C-7RTCD-MDVJX",
      "Microsoft Windows Server 2012 (64-bit)" => "BN3D2-R7TKB-3YPBD-8DRP2-27GG4",
    }.freeze

    # Configuration values for Guest Customization
    #
    # @returns [Hash] Configuration values from file
    def guest_customization
      options[:guest_customization]
    end

    # Build CustomizationSpec for Guest OS Customization
    #
    # @returns [RbVmomi::VIM::CustomizationSpec] Customization Spec for guest adjustments
    def guest_customization_spec
      return unless guest_customization

      guest_customization_validate_options

      if guest_customization[:ip_address]
        customized_ip = RbVmomi::VIM::CustomizationIPSettings.new(
          ip: RbVmomi::VIM::CustomizationFixedIp(ipAddress: guest_customization[:ip_address]),
          gateway: guest_customization[:gateway],
          subnetMask: guest_customization[:subnet_mask],
          dnsDomain: guest_customization[:dns_domain]
        )
      else
        customized_ip = RbVmomi::VIM::CustomizationIPSettings.new(
          ip: RbVmomi::VIM::CustomizationDhcpIpGenerator.new,
          dnsDomain: guest_customization[:dns_domain]
        )
      end

      RbVmomi::VIM::CustomizationSpec.new(
        identity: guest_customization_identity,
        globalIPSettings: RbVmomi::VIM::CustomizationGlobalIPSettings.new(
          dnsServerList: guest_customization[:dns_server_list],
          dnsSuffixList: guest_customization[:dns_suffix_list]
        ),
        nicSettingMap: [RbVmomi::VIM::CustomizationAdapterMapping.new(
          adapter: customized_ip
        )]
      )
    end

    # Check options for existance and format
    #
    # @raise [Support::GuestCustomizationOptionsError] For any violation
    def guest_customization_validate_options
      if guest_customization_ip_change?
        unless ip?(guest_customization[:ip_address])
          raise Support::GuestCustomizationOptionsError.new("Parameter `ip_address` is required to be formatted as an IPv4 address")
        end

        unless guest_customization[:subnet_mask]
          raise Support::GuestCustomizationOptionsError.new("Parameter `subnet_mask` is required if assigning a fixed IPv4 address")
        end

        unless ip?(guest_customization[:subnet_mask])
          raise Support::GuestCustomizationOptionsError.new("Parameter `subnet_mask` is required to be formatted as an IPv4 address")
        end

        if up?(guest_customization[:ip_address])
          raise Support::GuestCustomizationOptionsError.new("Parameter `ip_address` points to a host reachable via ICMP") unless guest_customization[:continue_on_ip_conflict]

          Kitchen.logger.warn("Continuing customization despite `ip_address` conflicting with a reachable host per user request")
        end
      end

      if guest_customization[:gateway]
        unless guest_customization[:gateway].is_a?(Array)
          raise Support::GuestCustomizationOptionsError.new("Parameter `gateway` must be an array")
        end

        guest_customization[:gateway].each do |v|
          unless ip?(v)
            raise Support::GuestCustomizationOptionsError.new("Parameter `gateway` is required to be formatted as an IPv4 address")
          end
        end
      end

      required = %i{dns_domain dns_server_list dns_suffix_list}
      missing = required - guest_customization.keys
      unless missing.empty?
        raise Support::GuestCustomizationOptionsError.new("Parameters `#{missing.join("`, `")}` are required to support guest customization")
      end

      guest_customization[:dns_server_list].each do |v|
        unless ip?(v)
          raise Support::GuestCustomizationOptionsError.new("Parameter `dns_server_list` is required to be formatted as an IPv4 address")
        end
      end

      if !guest_customization[:dns_server_list].is_a?(Array)
        raise Support::GuestCustomizationOptionsError.new("Parameter `dns_server_list` must be an array")
      elsif !guest_customization[:dns_suffix_list].is_a?(Array)
        raise Support::GuestCustomizationOptionsError.new("Parameter `dns_suffix_list` must be an array")
      end
    end

    # Check if an IP change is requested
    #
    # @returns [Boolean] If `ip_address` is to be changed
    def guest_customization_ip_change?
      guest_customization[:ip_address]
    end

    # Return OS-specific CustomizationIdentity object
    def guest_customization_identity
      if linux?
        guest_customization_identity_linux
      elsif windows?
        guest_customization_identity_windows
      else
        raise Support::GuestCustomizationError.new("Unknown OS, no valid customization found")
      end
    end

    # Construct Linux-specific customization information
    def guest_customization_identity_linux
      timezone = guest_customization[:timezone]
      if timezone && !valid_linux_timezone?(timezone)
        raise Support::GuestCustomizationError.new <<~ERROR
          Linux customization requires `timezone` in `Area/Location` format.
          See https://kb.vmware.com/s/article/2145518
        ERROR
      end

      Kitchen.logger.warn("Linux guest customization: No timezone passed, assuming UTC") unless timezone

      RbVmomi::VIM::CustomizationLinuxPrep.new(
        domain: guest_customization[:dns_domain],
        hostName: guest_hostname,
        hwClockUTC: true,
        timeZone: timezone || DEFAULT_LINUX_TIMEZONE
      )
    end

    # Construct Windows-specific customization information
    def guest_customization_identity_windows
      timezone = guest_customization[:timezone]
      if timezone && !valid_windows_timezone?(timezone)
        raise Support::GuestCustomizationOptionsError.new <<~ERROR
          Windows customization requires `timezone` as decimal number or hex number (0x55).
          See https://support.microsoft.com/en-us/help/973627/microsoft-time-zone-index-values
        ERROR
      end

      Kitchen.logger.warn("Windows guest customization: No timezone passed, assuming UTC") unless timezone

      product_id = guest_customization[:product_id]

      # Try to look up and use a known, documented 120-day trial key
      unless product_id
        guest_os = src_vm.guest&.guestFullName
        product_id = windows_kms_for_guest(guest_os)

        Kitchen.logger.warn format("Windows guest customization:: Using KMS Key `%<key>s` for %<os>s", key: product_id, os: guest_os) if product_id
      end

      unless valid_windows_key? product_id
        raise Support::GuestCustomizationOptionsError.new <<~ERROR
          Windows customization requires `product_id` to work. Add a valid product key or
          see https://docs.microsoft.com/en-us/windows-server/get-started/kmsclientkeys for KMS trial keys
        ERROR
      end

      RbVmomi::VIM::CustomizationSysprep.new(
        guiUnattended: RbVmomi::VIM::CustomizationGuiUnattended.new(
          timeZone: timezone.to_i || DEFAULT_WINDOWS_TIMEZONE,
          autoLogon: false,
          autoLogonCount: 1
        ),
        identification: RbVmomi::VIM::CustomizationIdentification.new,
        userData: RbVmomi::VIM::CustomizationUserData.new(
          computerName: guest_hostname,
          fullName: guest_customization[:org_name] || DEFAULT_WINDOWS_ORG,
          orgName: guest_customization[:org_name] || DEFAULT_WINDOWS_ORG,
          productId: product_id
        )
      )
    end

    # Check if a host is reachable
    def up?(host)
      check = Net::Ping::External.new(host)
      check.ping?
    end

    # Retrieve a GVLK (evaluation key) for the named OS
    #
    # @param [String] name Name of the OS as reported by VMware
    # @returns [String] GVLK key, if any
    def windows_kms_for_guest(name)
      WINDOWS_KMS_KEYS.fetch(name, false)
    end

    # Check format of Linux-specific timezone, according to VMware support
    #
    # @param [Integer] input Value to check for validity
    # @returns [Boolean] if value is valid
    def valid_linux_timezone?(input)
      # Specific to VMware: https://kb.vmware.com/s/article/2145518
      linux_timezone_pattern = %r{^[A-Z][A-Za-z]+\/[A-Z][-_+A-Za-z0-9]+$}

      input.to_s.match? linux_timezone_pattern
    end

    # Check format of Windows-specific timezone
    #
    # @param [Integer] input Value to check for validity
    # @returns [Boolean] if value is valid
    def valid_windows_timezone?(input)
      # Accept decimals and hex
      # See https://support.microsoft.com/en-us/help/973627/microsoft-time-zone-index-values
      windows_timezone_pattern = /^([0-9]+|0x[0-9a-fA-F]+)$/

      input.to_s.match? windows_timezone_pattern
    end

    # Check for format of Windows Product IDs
    #
    # @param [String] input String to check
    # @returns [Boolean] if value is in Windows Key format
    def valid_windows_key?(input)
      windows_key_pattern = /^[A-Z0-9]{5}-[A-Z0-9]{5}-[A-Z0-9]{5}-[A-Z0-9]{5}-[A-Z0-9]{5}$/

      input.to_s.match? windows_key_pattern
    end

    # Return Guest hostname to be configured and check for validity.
    #
    # @returns [String] New hostname to assign
    def guest_hostname
      hostname = guest_customization[:hostname] || options[:vm_name]

      hostname_pattern = /^([a-zA-Z0-9]|[a-zA-Z0-9][a-zA-Z0-9\-]*[a-zA-Z0-9])$/
      unless hostname.match?(hostname_pattern)
        raise Support::GuestCustomizationError.new("Only letters, numbers or hyphens in hostnames allowed")
      end

      RbVmomi::VIM::CustomizationFixedName.new(name: hostname)
    end

    # Wait for vSphere task completion and subsequent IP address update (if any).
    def guest_customization_wait
      guest_customization_wait_task(guest_customization[:timeout_task] || DEFAULT_TIMEOUT_TASK)
      guest_customization_wait_ip(guest_customization[:timeout_ip] || DEFAULT_TIMEOUT_IP)
    end

    # Wait for Guest customization to finish successfully.
    #
    # @param [Integer] timeout Timeout in seconds
    # @param [Integer] sleep_time Time to wait between tries
    def guest_customization_wait_task(timeout = 600, sleep_time = 10)
      waited_seconds = 0

      Kitchen.logger.info "Waiting for guest customization (timeout: #{timeout} seconds)..."

      while waited_seconds < timeout
        events = guest_customization_events

        if events.any? { |event| event.is_a? RbVmomi::VIM::CustomizationSucceeded }
          return
        elsif (failed = events.detect { |event| event.is_a? RbVmomi::VIM::CustomizationFailed })
          # Only matters for Linux, as Windows won't come up at all to report a failure via VMware Tools
          raise Support::GuestCustomizationError.new("Customization of VM failed: #{failed.fullFormattedMessage}")
        end

        sleep(sleep_time)
        waited_seconds += sleep_time
      end

      raise Support::GuestCustomizationError.new("Customization of VM did not complete within #{timeout} seconds.")
    end

    # Wait for new IP to be reported, if any.
    #
    # @param [Integer] timeout Timeout in seconds. Tools report every 30 seconds, Default: 30 seconds
    def guest_customization_wait_ip(timeout = 30)
      return unless guest_customization_ip_change?

      waited_seconds = 0

      Kitchen.logger.info "Waiting for guest customization IP update..."

      while waited_seconds < timeout
        found_ip = wait_for_ip(timeout, 1.0)

        return if found_ip == guest_customization[:ip_address]

        sleep(sleep_time)
        waited_seconds += sleep_time
      end

      raise Support::GuestCustomizationError.new("Customized IP was not reported within #{timeout} seconds.")
    end

    # Filter Customization events for the current VM
    #
    # @returns [Array<RbVmomi::VIM::CustomizationEvent>] All matching events
    def guest_customization_events
      vm_events %w{CustomizationSucceeded CustomizationFailed CustomizationStartedEvent}
    end
  end
end
