require "kitchen"
require "rbvmomi"

class Support
  class CloneVm
    attr_reader :vim, :options, :vm, :name, :path, :ip

    def initialize(conn_opts, options)
      @options = options
      @name = options[:name]

      # Connect to vSphere
      @vim ||= RbVmomi::VIM.connect conn_opts
    end

    def get_ip(vm)
      @ip = nil

      # Don't simply use vm.guest.ipAddress to allow specifying a different interface
      unless vm.guest.net.empty? || !vm.guest.ipAddress
        nics = vm.guest.net
        if options[:interface]
          nics.select! { |nic| nic.network == options[:interface] }

          raise format("No interfaces found on VM which are attached to network '%s'", options[:interface]) if nics.empty?
        end

        vm_ip = nil
        nics.each do |net|
          vm_ip = net.ipConfig.ipAddress.detect { |addr| addr.origin != "linklayer" }
          break unless vm_ip.nil?
        end

        extended_msg = options[:interface] ? "Network #{options[:interface]}" : ""
        raise format("No valid IP found on VM %s", extended_msg) if vm_ip.nil?

        @ip = vm_ip.ipAddress
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
      raise format("Error getting accessible IP address, got %s. Check DHCP server and scope exhaustion", ip) if ip =~ /^169\.254\./
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

        networks = dc.network.select { |n| n.name == options[:network_name] }
        raise format("Could not find network named %s", option[:network_name]) if networks.empty?

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
          raise format("Unknown network type %s for network name %s", network_obj.class.to_s, options[:network_name])
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
      if options[:clone_type] == :instant
        vcenter_data = vim.serviceInstance.content.about
        raise "Instant clones only supported with vCenter 6.7 or higher" unless vcenter_data.version.to_f >= 6.7
        Kitchen.logger.debug format("Detected %s", vcenter_data.fullName)

        resources = dc.hostFolder.children
        hosts = resources.select { |resource| resource.class.to_s =~ /ComputeResource$/ }.map { |c| c.host }.flatten
        targethost = hosts.select { |host| host.summary.config.name == options[:targethost].name }.first
        raise "No matching ComputeResource found in host folder" if targethost.nil?

        esx_data = targethost.summary.config.product
        raise "Instant clones only supported with ESX 6.7 or higher" unless esx_data.version.to_f >= 6.7
        Kitchen.logger.debug format("Detected %s", esx_data.fullName)

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
      @path = options[:folder].nil? ? name : format("%s/%s", options[:folder][:name], name)
      @vm = dc.find_vm(path)

      raise format("Unable to find machine: %s", path) if vm.nil?

      # Pass contents of the customization option/Hash through to allow full customization
      # https://pubs.vmware.com/vsphere-6-5/index.jsp?topic=%2Fcom.vmware.wssdk.smssdk.doc%2Fvim.vm.ConfigSpec.html
      unless options[:customize].nil?
        Kitchen.logger.info "Waiting for reconfiguration to finish"

        config_spec = RbVmomi::VIM.VirtualMachineConfigSpec(options[:customize])
        task = vm.ReconfigVM_Task(spec: config_spec)
        task.wait_for_completion
      end

      if options[:poweron] && !options[:customize].nil? && options[:clone_type] != :instant
        task = vm.PowerOnVM_Task
        task.wait_for_completion
      end

      Kitchen.logger.info format("Waiting for VMware tools/network interfaces to become available (timeout: %d seconds)...", options[:wait_timeout])

      wait_for_ip(vm, options[:wait_timeout], options[:wait_interval])
      Kitchen.logger.info format("Created machine %s with IP %s", name, ip)
    end
  end
end
