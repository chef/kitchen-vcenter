require "kitchen"
require "rbvmomi"
require "support/guest_operations"

class Support
  class CloneError < RuntimeError; end

  class CloneVm
    attr_reader :vim, :options, :ssl_verify, :vm, :name, :ip

    def initialize(conn_opts, options)
      @options = options
      @name = options[:name]
      @ssl_verify = !conn_opts[:insecure]

      # Connect to vSphere
      @vim ||= RbVmomi::VIM.connect conn_opts
    end

    def aggressive_discovery?
      options[:aggressive] == true
    end

    def ip_from_tools
      return if vm.guest.net.empty?

      # Don't simply use vm.guest.ipAddress to allow specifying a different interface
      nics = vm.guest.net
      if options[:interface]
        nics.select! { |nic| nic.network == options[:interface] }

        raise Support::CloneError.new(format("No interfaces found on VM which are attached to network '%s'", options[:interface])) if nics.empty?
      end

      vm_ip = nil
      nics.each do |net|
        vm_ip = net.ipConfig.ipAddress.detect { |addr| addr.origin != "linklayer" }
        break unless vm_ip.nil?
      end

      extended_msg = options[:interface] ? "Network #{options[:interface]}" : ""
      raise Support::CloneError.new(format("No valid IP found on VM %s", extended_msg)) if vm_ip.nil?
      vm_ip.ipAddress
    end

    def wait_for_tools(timeout = 30.0, interval = 2.0)
      start = Time.new

      loop do
        if vm.guest.toolsRunningStatus == "guestToolsRunning"
          Kitchen.logger.debug format("Tools detected after %d seconds", Time.new - start)
          return
        end
        break if (Time.new - start) >= timeout
        sleep interval
      end

      raise Support::CloneError.new("Timeout waiting for VMware Tools")
    end

    def wait_for_ip(timeout = 60.0, interval = 2.0)
      start = Time.new

      ip = nil
      loop do
        ip = ip_from_tools
        if ip || (Time.new - start) >= timeout
          Kitchen.logger.debug format("IP retrieved after %d seconds", Time.new - start) if ip
          break
        end
        sleep interval
      end

      raise Support::CloneError.new("Timeout waiting for IP address") if ip.nil?
      raise Support::CloneError.new(format("Error getting accessible IP address, got %s. Check DHCP server and scope exhaustion", ip)) if ip =~ /^169\.254\./

      @ip = ip
    end

    def detect_os
      vm.config&.guestId =~ /^win/ ? :windows : :linux
    end

    def standard_ip_discovery
      Kitchen.logger.info format("Waiting for IP (timeout: %d seconds)...", options[:wait_timeout])
      wait_for_ip(options[:wait_timeout], options[:wait_interval])
    end

    def aggressive_ip_discovery
      return unless aggressive_discovery? && !instant_clone?

      # Take guest OS from VM/Template configuration, if not explicitly configured
      # @see https://pubs.vmware.com/vsphere-6-5/index.jsp?topic=%2Fcom.vmware.wssdk.apiref.doc%2Fvim.vm.GuestOsDescriptor.GuestOsIdentifier.html
      if options[:aggressive_os].nil?
        os = detect_os
        Kitchen.logger.warn format('OS for aggressive mode not configured, got "%s" from VMware', os.to_s.capitalize)
        options[:aggressive_os] = os
      end

      case options[:aggressive_os].downcase.to_sym
      when :linux
        discovery_command = "ip addr | grep global | cut -b10- | cut -d/ -f1"
      when :windows
        # discovery_command = "(Test-Connection -Computername $env:COMPUTERNAME -Count 1).IPV4Address.IPAddressToString"
        discovery_command = "wmic nicconfig get IPAddress"
      end

      username = options[:aggressive_username]
      password = options[:aggressive_password]
      guest_auth = RbVmomi::VIM::NamePasswordAuthentication(interactiveSession: false, username: username, password: password)

      Kitchen.logger.info "Attempting aggressive IP discovery"
      begin
        tools = Support::GuestOperations.new(vim, vm, guest_auth, ssl_verify)
        stdout = tools.run_shell_capture_output(discovery_command)

        # Windows returns wrongly encoded UTF-8 for some reason
        stdout = stdout.bytes.map { |b| (32..126).cover?(b.ord) ? b.chr : nil }.join unless stdout.ascii_only?
        @ip = stdout.match(/([0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3})/m).captures.first
      rescue RbVmomi::Fault => e
        if e.fault.class.wsdl_name == "InvalidGuestLogin"
          message = format('Error authenticating to guest OS as "%s", check configuration of "aggressive_username"/"aggressive_password"', username)
        end

        raise Support::CloneError.new(message)
      rescue ::StandardError
        Kitchen.logger.info "Aggressive discovery failed. Trying standard discovery method."
        return false
      end

      true
    end

    def reconfigure_guest
      Kitchen.logger.info "Waiting for reconfiguration to finish"

      # Pass contents of the customization option/Hash through to allow full customization
      # https://pubs.vmware.com/vsphere-6-5/index.jsp?topic=%2Fcom.vmware.wssdk.smssdk.doc%2Fvim.vm.ConfigSpec.html
      config_spec = RbVmomi::VIM.VirtualMachineConfigSpec(options[:customize])

      task = vm.ReconfigVM_Task(spec: config_spec)
      task.wait_for_completion
    end

    def instant_clone?
      options[:clone_type] == :instant
    end

    def linked_clone?
      options[:clone_type] == :linked
    end

    def full_clone?
      options[:clone_type] == :full
    end

    def clone
      # set the datacenter name
      dc = vim.serviceInstance.find_datacenter(options[:datacenter])

      # reference template using full inventory path
      root_folder = vim.serviceInstance.content.rootFolder
      inventory_path = format("/%s/vm/%s", options[:datacenter], options[:template])
      src_vm = root_folder.findByInventoryPath(inventory_path)
      raise Support::CloneError.new(format("Unable to find template: %s", options[:template])) if src_vm.nil?

      # Specify where the machine is going to be created
      relocate_spec = RbVmomi::VIM.VirtualMachineRelocateSpec

      # Setting the host is not allowed for instant clone due to VM memory sharing
      relocate_spec.host = options[:targethost].host unless instant_clone?

      # Change to delta disks for linked clones
      relocate_spec.diskMoveType = :moveChildMostDiskBacking if linked_clone?

      # Set the resource pool
      relocate_spec.pool = options[:resource_pool]

      # Change network, if wanted
      unless options[:network_name].nil?
        all_network_devices = src_vm.config.hardware.device.select do |device|
          device.is_a?(RbVmomi::VIM::VirtualEthernetCard)
        end

        # Only support for first NIC so far
        network_device = all_network_devices.first

        networks = dc.network.select { |n| n.name == options[:network_name] }
        raise Support::CloneError.new(format("Could not find network named %s", option[:network_name])) if networks.empty?

        Kitchen.logger.warn format("Found %d networks named %s, picking first one", networks.count, options[:network_name]) if networks.count > 1
        network_obj = networks.first

        if network_obj.is_a? RbVmomi::VIM::DistributedVirtualPortgroup
          Kitchen.logger.info format("Assigning network %s...", network_obj.pretty_path)

          vds_obj = network_obj.config.distributedVirtualSwitch
          Kitchen.logger.info format("Using vDS '%s' for network connectivity...", vds_obj.name)

          network_device.backing = RbVmomi::VIM.VirtualEthernetCardDistributedVirtualPortBackingInfo(
            port: RbVmomi::VIM.DistributedVirtualSwitchPortConnection(
              portgroupKey: network_obj.key,
              switchUuid: vds_obj.uuid
            )
          )
        elsif network_obj.is_a? RbVmomi::VIM::Network
          Kitchen.logger.info format("Assigning network %s...", options[:network_name])

          network_device.backing = RbVmomi::VIM.VirtualEthernetCardNetworkBackingInfo(
            deviceName: options[:network_name]
          )
        else
          raise Support::CloneError.new(format("Unknown network type %s for network name %s", network_obj.class.to_s, options[:network_name]))
        end

        relocate_spec.deviceChange = [
          RbVmomi::VIM.VirtualDeviceConfigSpec(
            operation: RbVmomi::VIM::VirtualDeviceConfigSpecOperation("edit"),
            device: network_device
          )
        ]
      end

      # Set the folder to use
      dest_folder = options[:folder].nil? ? dc.vmFolder : options[:folder][:id]

      Kitchen.logger.info format("Cloning '%s' to create the VM...", options[:template])
      if instant_clone?
        vcenter_data = vim.serviceInstance.content.about
        raise Support::CloneError.new("Instant clones only supported with vCenter 6.7 or higher") unless vcenter_data.version.to_f >= 6.7
        Kitchen.logger.debug format("Detected %s", vcenter_data.fullName)

        resources = dc.hostFolder.children
        hosts = resources.select { |resource| resource.class.to_s =~ /ComputeResource$/ }.map { |c| c.host }.flatten
        targethost = hosts.select { |host| host.summary.config.name == options[:targethost].name }.first
        raise Support::CloneError.new("No matching ComputeResource found in host folder") if targethost.nil?

        esx_data = targethost.summary.config.product
        raise Support::CloneError.new("Instant clones only supported with ESX 6.7 or higher") unless esx_data.version.to_f >= 6.7
        Kitchen.logger.debug format("Detected %s", esx_data.fullName)

        # Other tools check for VMWare Tools status, but that will be toolsNotRunning on frozen VMs
        raise Support::CloneError.new("Need a running VM for instant clones") unless src_vm.runtime.powerState == "poweredOn"

        # In first iterations, only support the Frozen Source VM workflow. This is more efficient
        #   but needs preparations (freezing the source VM). Running Source VM support is to be
        #   added later
        raise Support::CloneError.new("Need a frozen VM for instant clones, running source VM not supported yet") unless src_vm.runtime.instantCloneFrozen

        # Swapping NICs not needed anymore (blog posts mention this), instant clones get a new
        # MAC at least with 6.7.0 build 9433931

        clone_spec = RbVmomi::VIM.VirtualMachineInstantCloneSpec(location: relocate_spec,
                                                                 name: name)

        task = src_vm.InstantClone_Task(spec: clone_spec)
      else
        clone_spec = RbVmomi::VIM.VirtualMachineCloneSpec(location: relocate_spec,
                                                          powerOn: options[:poweron] && options[:customize].nil?,
                                                          template: false)

        task = src_vm.CloneVM_Task(spec: clone_spec, folder: dest_folder, name: name)
      end
      task.wait_for_completion

      # get the IP address of the machine for bootstrapping
      # machine name is based on the path, e.g. that includes the folder
      path = options[:folder].nil? ? name : format("%s/%s", options[:folder][:name], name)
      @vm = dc.find_vm(path)
      raise Support::CloneError.new(format("Unable to find machine: %s", path)) if vm.nil?

      reconfigure_guest unless options[:customize].nil?

      if options[:poweron] && !options[:customize].nil? && !instant_clone?
        task = vm.PowerOnVM_Task
        task.wait_for_completion
      end

      Kitchen.logger.info format("Waiting for VMware tools to become available (timeout: %d seconds)...", options[:wait_timeout])
      wait_for_tools(options[:wait_timeout], options[:wait_interval])

      aggressive_ip_discovery || standard_ip_discovery

      Kitchen.logger.info format("Created machine %s with IP %s", name, ip)
    end
  end
end
