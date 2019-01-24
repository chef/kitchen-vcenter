require "rbvmomi"

class Support
  class CloneVm
    attr_reader :vim, :options

    def initialize(conn_opts, options)
      @options = options

      # Connect to vSphere
      @vim ||= RbVmomi::VIM.connect conn_opts
    end

    def get_ip(vm)
      ip = nil

      unless vm.guest.net.empty? || !vm.guest.ipAddress
        ip = vm.guest.net[0].ipConfig.ipAddress.detect do |addr|
          addr.origin != "linklayer"
        end.ipAddress
      end

      ip
    end

    def wait_for_ip(vm, timeout = 30.0, interval = 2.0)
      start = Time.new

      ip = nil
      loop do
        ip = get_ip(vm)
        break if ip || (Time.new - start) >= timeout
        sleep interval
      end

      raise "Timeout waiting for IP address or no VMware Tools installed on guest" if ip.nil?
      raise format("Error getting accessible IP address, got %s. Check DHCP server", ip) if ip =~ /^169\.254\./

      ip
    end

    def clone
      # set the datacenter name
      dc = vim.serviceInstance.find_datacenter(options[:datacenter])

      # reference template using full inventory path
      root_folder = @vim.serviceInstance.content.rootFolder
      inventory_path = format("/%s/vm/%s", options[:datacenter], options[:template])
      src_vm = root_folder.findByInventoryPath(inventory_path)
      raise format("Unable to find template: %s", options[:template]) if src_vm.nil?

      # Specify where the machine is going to be created
      relocate_spec = RbVmomi::VIM.VirtualMachineRelocateSpec

      # Setting the host is not allowed for instant clone due to VM memory sharing
      relocate_spec.host = options[:targethost].host unless options[:clone_type] == :instant

      # Change to delta disks for linked clones
      relocate_spec.diskMoveType = :moveChildMostDiskBacking if options[:clone_type] == :linked

      # Set the resource pool
      relocate_spec.pool = options[:resource_pool]

      # Change network, if wanted
      unless options[:network_name].nil?
        all_network_devices = src_vm.config.hardware.device.select do |device|
          device.is_a?(RbVmomi::VIM::VirtualEthernetCard)
        end

        # Only support for first NIC so far
        network_device = all_network_devices.first
        network_device.backing = RbVmomi::VIM.VirtualEthernetCardNetworkBackingInfo(
          deviceName: options[:network_name]
        )

        relocate_spec.deviceChange = [
          RbVmomi::VIM.VirtualDeviceConfigSpec(
            operation: RbVmomi::VIM::VirtualDeviceConfigSpecOperation("edit"),
            device: network_device
          )
        ]
      end

      # Set the folder to use
      dest_folder = options[:folder].nil? ? dc.vmFolder : options[:folder][:id]

      puts "Cloning '#{options[:template]}' to create the VM..."
      if options[:clone_type] == :instant
        vcenter_data = vim.serviceInstance.content.about
        raise "Instant clones only supported with vCenter 6.7 or higher" unless vcenter_data.version.to_f >= 6.7
        puts "- Detected #{vcenter_data.fullName}"

        resources = dc.hostFolder.children
        hosts = resources.select { |resource| resource.class.to_s == "ComputeResource" }.map { |c| c.host }.flatten
        targethost = hosts.select { |host| host.summary.config.name == options[:targethost].name }.first
        esx_data = targethost.summary.config.product
        raise "Instant clones only supported with ESX 6.7 or higher" unless esx_data.version.to_f >= 6.7
        puts "- Detected #{esx_data.fullName}"

        # Other tools check for VMWare Tools status, but that will be toolsNotRunning on frozen VMs
        raise "Need a running VM for instant clones" unless src_vm.runtime.powerState == "poweredOn"

        # In first iterations, only support the Frozen Source VM workflow. This is more efficient
        #   but needs preparations (freezing the source VM). Running Source VM support is to be
        #   added later
        raise "Need a frozen VM for instant clones, running source VM not supported yet" unless src_vm.runtime.instantCloneFrozen

        # Swapping NICs not needed anymore (blog posts mention this), instant clones get a new
        # MAC at least with 6.7.0 build 9433931

        # @todo not working yet
        # relocate_spec.folder = dest_folder
        clone_spec = RbVmomi::VIM.VirtualMachineInstantCloneSpec(location: relocate_spec,
                                                                 name: options[:name])

        task = src_vm.InstantClone_Task(spec: clone_spec)
      else
        clone_spec = RbVmomi::VIM.VirtualMachineCloneSpec(location: relocate_spec,
                                                          powerOn: options[:poweron],
                                                          template: false)

        task = src_vm.CloneVM_Task(spec: clone_spec, folder: dest_folder, name: options[:name])
      end
      task.wait_for_completion

      # get the IP address of the machine for bootstrapping
      # machine name is based on the path, e.g. that includes the folder
      name = options[:folder].nil? ? options[:name] : format("%s/%s", options[:folder][:name], options[:name])
      new_vm = dc.find_vm(name)

      if new_vm.nil?
        puts format("Unable to find machine: %s", name)
      else
        puts format("Waiting for VMware tools/network interfaces to become available (timeout: %d seconds)...", options[:wait_timeout])

        ip = wait_for_ip(new_vm, options[:wait_timeout], options[:wait_interval])
        puts format("Created machine %s with IP %s", name, ip)

        ip
      end
    end
  end
end
