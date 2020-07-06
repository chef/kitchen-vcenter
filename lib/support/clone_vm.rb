require "kitchen"
require "rbvmomi"
require_relative "guest_operations"

class Support
  class CloneError < RuntimeError; end

  class CloneVm
    attr_reader :vim, :options, :ssl_verify, :vm, :name, :ip, :guest_auth, :username, :post_create

    def initialize(conn_opts, options)
      @options = options
      @name = options[:name]
      @ssl_verify = !conn_opts[:insecure]

      # Connect to vSphere
      @vim ||= RbVmomi::VIM.connect conn_opts

      @username = options[:vm_username] || kitchen_transport_config[:username]
      password = options[:vm_password] || kitchen_transport_config[:password]
      @guest_auth = RbVmomi::VIM::NamePasswordAuthentication(interactiveSession: false, username: username, password: password)

      @benchmark_data = {}
      @post_create = []
    end

    def kitchen
      require "binding_of_caller"
      binding.callers.find { |b| b.frame_description == "create" && b.receiver.class == Kitchen::Instance }.receiver
    end

    def kitchen_transport_config
      kitchen.transport.send(:provided_config)
    end

    def active_discovery?
      options[:active_discovery] == true
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

      vm_ip&.ipAddress
    end

    def wait_for_tools(timeout = 30.0, interval = 2.0)
      start = Time.new

      loop do
        if vm.guest.toolsRunningStatus == "guestToolsRunning"
          benchmark_checkpoint("tools_detected")

          Kitchen.logger.debug format("Tools detected after %.1f seconds", Time.new - start)
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
          Kitchen.logger.debug format("IP retrieved after %.1f seconds", Time.new - start) if ip
          break
        end
        sleep interval
      end

      raise Support::CloneError.new("Timeout waiting for IP address") if ip.nil?
      raise Support::CloneError.new(format("Error getting accessible IP address, got %s. Check DHCP server and scope exhaustion", ip)) if ip =~ /^169\.254\./

      # Allow IP rewriting (e.g. for 1:1 NAT)
      if options[:transform_ip]
        Kitchen.logger.info format("Received IP: %s", ip)

        # rubocop:disable Security/Eval
        ip = lambda { eval options[:transform_ip] }.call
        # rubocop:enable Security/Eval

        Kitchen.logger.info format("Transformed to IP: %s", ip)
      end

      @ip = ip
    end

    def benchmark?
      options[:benchmark] == true
    end

    def benchmark_file
      options[:benchmark_file]
    end

    def benchmark_start
      return unless benchmark?

      Kitchen.logger.debug("Starting benchmark data collection.")

      @benchmark_data = {
        template: options[:template],
        clonetype: options[:clone_type],
        checkpoints: [
          { title: "timestamp", value: Time.new.to_f },
        ],
      }
    end

    def benchmark_checkpoint(title)
      return unless benchmark?

      timestamp = Time.new
      checkpoints = @benchmark_data[:checkpoints]

      total = timestamp - checkpoints.first.fetch(:value)
      Kitchen.logger.debug format(
        'Benchmark: Step "%s" at %d (%.1f since start)',
        title, timestamp, total.to_f
      )

      @benchmark_data[:checkpoints] << {
        title: title.to_sym,
        value: total,
      }
    end

    def benchmark_persist
      return unless benchmark?

      # Add total time spent as well
      checkpoints = @benchmark_data[:checkpoints]
      checkpoints << {
        title: :total,
        value: Time.new - checkpoints.first.fetch(:value),
      }

      # Include CSV headers
      unless File.exist?(benchmark_file)
        header = "template, clonetype, active_discovery, "
        header += checkpoints.map { |entry| entry[:title] }.join(", ") + "\n"
        File.write(benchmark_file, header)
      end

      active_discovery = options[:active_discovery] || instant_clone?
      data = [@benchmark_data[:template], @benchmark_data[:clonetype], active_discovery.to_s]
      data << checkpoints.map { |entry| format("%.1f", entry[:value]) }

      file = File.new(benchmark_file, "a")
      file.puts(data.join(", ") + "\n")

      Kitchen.logger.debug format("Benchmark: Appended data to file %s", benchmark_file)
    end

    def detect_os
      vm.config&.guestId&.match(/^win/) ? :windows : :linux
    end

    def windows?
      options[:vm_os].downcase.to_sym == :windows
    end

    def linux?
      options[:vm_os].downcase.to_sym == :linux
    end

    def network_device(vm)
      all_network_devices = vm.config.hardware.device.select do |device|
        device.is_a?(RbVmomi::VIM::VirtualEthernetCard)
      end

      # Only support for first NIC so far
      all_network_devices.first
    end

    def reconnect_network_device(vm)
      network_device = network_device(vm)
      network_device.connectable = RbVmomi::VIM.VirtualDeviceConnectInfo(
        allowGuestControl: true,
        startConnected: true,
        connected: true
      )

      config_spec = RbVmomi::VIM.VirtualMachineConfigSpec(
        deviceChange: [
          RbVmomi::VIM.VirtualDeviceConfigSpec(
            operation: RbVmomi::VIM::VirtualDeviceConfigSpecOperation("edit"),
            device: network_device
          ),
        ]
      )

      task = vm.ReconfigVM_Task(spec: config_spec)
      task.wait_for_completion

      benchmark_checkpoint("nic_reconfigured")
    end

    def standard_ip_discovery
      Kitchen.logger.info format("Waiting for IP (timeout: %d seconds)...", options[:wait_timeout])
      wait_for_ip(options[:wait_timeout], options[:wait_interval])
    end

    def command_separator
      case options[:vm_os].downcase.to_sym
      when :linux
        " && "
      when :windows
        " & "
      end
    end

    # Rescan network adapters for MAC/IP changes
    def rescan_commands
      Kitchen.logger.info "Refreshing network interfaces in OS"

      case options[:vm_os].downcase.to_sym
      when :linux
        # @todo: allow override if no dhclient
        [
          "/sbin/modprobe -r vmxnet3",
          "/sbin/modprobe vmxnet3",
          "/sbin/dhclient",
        ]
      when :windows
        [
          "netsh interface set Interface #{options[:vm_win_network]} disable",
          "netsh interface set Interface #{options[:vm_win_network]} enable",
          "ipconfig /renew",
        ]
      end
    end

    # Available from VMware Tools 10.1.0 this pushes the IP instead of the standard 30 second poll
    # This will be used to provide a quick fallback, if active discovery fails.
    def trigger_tools
      case options[:vm_os].downcase.to_sym
      when :linux
        [
          "/usr/bin/vmware-toolbox-cmd info update network",
        ]
      when :windows
        [
          '"C:\Program Files\VMware\VMware Tools\VMwareToolboxCmd.exe" info update network',
        ]
      end
    end

    # Retrieve IP via OS commands
    def discovery_commands
      if options[:active_discovery_command].nil?
        case options[:vm_os].downcase.to_sym
        when :linux
          "ip address show scope global | grep global | cut -b10- | cut -d/ -f1"
        when :windows
          ["sleep 5", "ipconfig"]
          # "ipconfig /renew"
          # "wmic nicconfig get IPAddress",
          # "netsh interface ip show ipaddress #{options[:vm_win_network]}"
        end
      else
        options[:active_discovery_command]
      end
    end

    def active_ip_discovery(prefix_commands = [])
      # Instant clone needs this to have synchronous reply on the new IP
      return unless active_discovery? || instant_clone?

      Kitchen.logger.info "Attempting active IP discovery"

      commands = []
      commands << rescan_commands if instant_clone?
      # commands << trigger_tools # deactivated for now, as benefit is doubtful
      commands << discovery_commands
      script = commands.flatten.join(command_separator)

      output = execute_via_tools(script)

      @ip = output.match(/([0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3})/m)&.captures&.first
      raise Support::CloneError.new(format("Could not find IP in script output, fallback to standard discovery")) if ip.nil?
      raise Support::CloneError.new(format("Error getting accessible IP address, got %s. Check DHCP server, scope exhaustion or timing issues", ip)) if ip =~ /^169\.254\./

      true

    rescue ::StandardError => e
      Kitchen.logger.info format("Active discovery failed: %s", e.message)

      false
    end

    def execute_via_tools(script, timeout = 20)
      Kitchen.logger.debug format("Script execution: %s", script)

      tools = Support::GuestOperations.new(vim, vm, guest_auth, ssl_verify)
      output = tools.run_shell_capture_output(script, :auto, timeout)
      output = sanitize_script_output(output) unless output.ascii_only?

      Kitchen.logger.debug format("Script output: %s", output)

      output

    rescue RbVmomi::Fault => e
      if e.fault.class.wsdl_name == "InvalidGuestLogin"
        message = format('Error authenticating to guest OS as "%s", check configuration of "vm_username"/"vm_password"', username)
      else
        message = e.message
      end

      raise Support::CloneError.new(message)
    end

    def sanitize_script_output(output)
      # Windows returns wrongly encoded UTF-8 for some reason
      output.bytes.map { |b| (32..126).cover?(b.ord) ? b.chr : nil }.join
    end

    def add_post_create_script(contents, name: nil)
      return unless contents

      @post_create << {
        name: name || format("unnamed-%d", Time.now.to_i),
        contents: contents,
      }
    end

    def post_create_scripts?
      !post_create.empty?
    end

    def execute_post_create_scripts
      return unless post_create_scripts?

      timeout = options[:post_create_script_timeout]

      post_create.each do |data|
        Kitchen.logger.info format("Running post create script '%s'", data[:name])

        output = execute_via_tools(data[:contents], timeout)
        Kitchen.logger.debug format("Script output: %s", output)
      end

      benchmark_checkpoint("post_create_script")
    end

    def check_add_disk_config(disk_config)
      valid_types = %w{thin flat flat_lazy flat_eager}

      unless valid_types.include? disk_config[:type].to_s
        message = format("Unknown disk type in add_disks: %s. Allowed: %s",
          disk_config[:type].to_s,
          valid_types.join(", "))

        raise Support::CloneError.new(message)
      end
    end

    def reconfigure_guest
      return unless options[:customize]

      Kitchen.logger.info "Waiting for reconfiguration to finish"

      # Pass some contents right through
      # https://pubs.vmware.com/vsphere-6-5/index.jsp?topic=%2Fcom.vmware.wssdk.smssdk.doc%2Fvim.vm.ConfigSpec.html
      config = options[:customize].select { |key, _| %i{annotation memoryMB numCPUs}.include? key }

      add_disks = options[:customize]&.fetch(:add_disks, nil)
      unless add_disks.nil?
        config[:deviceChange] = []

        # Will create a stem like "default-ubuntu-12345678/default-ubuntu-12345678"
        filename_base = vm.disks.first.backing.fileName.gsub(/(-[0-9]+)?.vmdk/, "")

        # Storage Controller and ID mapping
        controller = vm.config.hardware.device.select { |device| device.is_a? RbVmomi::VIM::VirtualSCSIController }.first

        add_disks.each_with_index do |disk_config, idx|
          # Default to Thin Provisioning and 10GB disk size
          disk_config[:type]    ||= :thin
          disk_config[:size_mb] ||= 10240

          check_add_disk_config(disk_config)

          disk_spec = RbVmomi::VIM.VirtualDeviceConfigSpec(
            fileOperation: "create",
            operation: RbVmomi::VIM::VirtualDeviceConfigSpecOperation("add"),
            device: RbVmomi::VIM.VirtualDisk(
              backing: RbVmomi::VIM.VirtualDiskFlatVer2BackingInfo(
                thinProvisioned: true,
                diskMode: "persistent",
                fileName: format("%s_disk%03d.vmdk", filename_base, idx + 1),
                datastore: vm.disks.first.backing.datastore
              ),
              deviceInfo: RbVmomi::VIM::Description(
                label: format("Additional disk %d", idx + 1),
                summary: format("%d MB", disk_config[:size_mb])
              )
            )
          )

          # capacityInKB is marked a deprecated in 6.7 but still a required parameter
          disk_spec.device.capacityInBytes = disk_config[:size_mb] * 1024**2
          disk_spec.device.capacityInKB = disk_config[:size_mb] * 1024

          disk_spec.device.controllerKey = controller.key

          highest_id = vm.disks.map(&:unitNumber).sort.last
          next_id = highest_id + idx + 1

          # Avoid the SCSI controller ID
          next_id += 1 if next_id == controller.scsiCtlrUnitNumber

          # Theoretically could add another SCSI controller, but there are limits to what kitchen should support
          if next_id > 14
            raise Support::CloneError.new(format("Ran out of SCSI IDs while trying to assign new disk %d", idx + 1))
          end

          disk_spec.device.unitNumber = next_id

          device_keys = vm.config.hardware.device.map(&:key).sort
          disk_spec.device.key = device_keys.last + (idx + 1) * 1000

          disk_spec.device.backing.eagerlyScrub = true if disk_config[:type].to_s == "flat_eager"
          disk_spec.device.backing.thinProvisioned = false if disk_config[:type].to_s =~ /^flat/

          config[:deviceChange] << disk_spec
        end
      end

      config_spec = RbVmomi::VIM.VirtualMachineConfigSpec(config)

      task = vm.ReconfigVM_Task(spec: config_spec)
      task.wait_for_completion

      benchmark_checkpoint("reconfigured")
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

    def root_folder
      @root_folder ||= vim.serviceInstance.content.rootFolder
    end

    #
    # @return [String]
    #
    def datacenter
      options[:datacenter]
    end

    #
    # @return [RbVmomi::VIM::Datacenter]
    #
    def find_datacenter
      vim.serviceInstance.find_datacenter(datacenter)
    rescue RbVmomi::Fault
      root_folder.childEntity.grep(RbVmomi::VIM::Datacenter).find { |x| x.name == datacenter }
    end

    def clone
      benchmark_start

      # set the datacenter name
      dc = find_datacenter

      # reference template using full inventory path
      inventory_path = format("/%s/vm/%s", datacenter, options[:template])
      src_vm = root_folder.findByInventoryPath(inventory_path)
      raise Support::CloneError.new(format("Unable to find template: %s", options[:template])) if src_vm.nil?

      if src_vm.config.template && !full_clone?
        Kitchen.logger.warn "Source is a template, thus falling back to full clone. Reference a VM for linked/instant clones."
        options[:clone_type] = :full
      end

      if src_vm.snapshot.nil? && !full_clone?
        Kitchen.logger.warn "Source VM has no snapshot available, thus falling back to full clone. Create a snapshot for linked/instant clones."
        options[:clone_type] = :full
      end

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
        networks = dc.network.select { |n| n.name == options[:network_name] }
        raise Support::CloneError.new(format("Could not find network named %s", options[:network_name])) if networks.empty?

        Kitchen.logger.warn format("Found %d networks named %s, picking first one", networks.count, options[:network_name]) if networks.count > 1
        network_obj = networks.first
        network_device = network_device(src_vm)

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
          ),
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
        hosts = resources.select { |resource| resource.class.to_s =~ /ComputeResource$/ }.map(&:host).flatten
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

        # Disconnect network device, so wo don't get IP collisions on start
        network_device = network_device(src_vm)
        network_device.connectable = RbVmomi::VIM.VirtualDeviceConnectInfo(
          allowGuestControl: true,
          startConnected: true,
          connected: false,
          migrateConnect: "disconnect"
        )
        relocate_spec.deviceChange = [
          RbVmomi::VIM.VirtualDeviceConfigSpec(
            operation: RbVmomi::VIM::VirtualDeviceConfigSpecOperation("edit"),
            device: network_device
          ),
        ]

        clone_spec = RbVmomi::VIM.VirtualMachineInstantCloneSpec(location: relocate_spec,
                                                                 name: name)

        benchmark_checkpoint("initialized")
        task = src_vm.InstantClone_Task(spec: clone_spec)
      else
        clone_spec = RbVmomi::VIM.VirtualMachineCloneSpec(location: relocate_spec,
                                                          powerOn: options[:poweron] && options[:customize].nil?,
                                                          template: false)

        benchmark_checkpoint("initialized")
        task = src_vm.CloneVM_Task(spec: clone_spec, folder: dest_folder, name: name)
      end
      task.wait_for_completion

      benchmark_checkpoint("cloned")

      # machine name is based on the path, e.g. that includes the folder
      path = options[:folder].nil? ? name : format("%s/%s", options[:folder][:name], name)
      @vm = dc.find_vm(path)
      raise Support::CloneError.new(format("Unable to find machine: %s", path)) if vm.nil?

      if options[:vm_os].nil?
        os = detect_os
        Kitchen.logger.debug format('OS for VM not configured, got "%s" from VMware', os.to_s.capitalize)
        options[:vm_os] = os
      end

      # Reconnect network device after Instant Clone is ready
      if instant_clone?
        Kitchen.logger.info "Reconnecting network adapter"
        reconnect_network_device(vm)
      end

      reconfigure_guest

      # Start only if specified or customizations wanted; no need for instant clones as they start in running state
      if options[:poweron] && !options[:customize].nil? && !instant_clone?
        task = vm.PowerOnVM_Task
        task.wait_for_completion
      end
      benchmark_checkpoint("powered_on")

      Kitchen.logger.info format("Waiting for VMware tools to become available (timeout: %d seconds)...", options[:wait_timeout])
      wait_for_tools(options[:wait_timeout], options[:wait_interval])

      add_post_create_script(options[:post_create_script], name: "kitchen.yml")

      execute_post_create_scripts

      active_ip_discovery || standard_ip_discovery
      benchmark_checkpoint("ip_detected")

      benchmark_persist

      Kitchen.logger.info format("Created machine %s with IP %s", name, ip)
    end
  end
end
