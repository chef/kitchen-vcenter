require "support/clone_vm"
require "securerandom"

describe Support::CloneVm do
  subject { described_class.new(connection_options, options) }

  let(:vcenter_host) { "my-vcenter-dream.company.com" }
  let(:vcenter_username) { "barney" }
  let(:vcenter_password) { "Sssh...I love Chef <3" }
  let(:vcenter_disable_ssl_verify) { false }
  let(:clone_type) { :full }
  let(:connection_options) do
    {
      user: vcenter_username,
      password: vcenter_password,
      insecure: false,
      host: vcenter_host,
      rev: "6.7",
      cookie: nil,
      ssl: true,
      port: 443,
      path: "/sdk",
      ns: "urn:vim25",
      debug: false,
    }
  end

  let(:folder_name) { "my-folder" }
  let(:folder_id) { "group-v123" }

  let(:options) {
    {
      vm_name: vm_name,
      targethost: target_host,
      poweron: true,
      template: "other-folder/my-template",
      datacenter: datacenter_name,
      folder: {
        name: folder_name,
        id: folder_id,
      },
      resource_pool: "resgroup-123",
      clone_type: :full,
      networks: [network_hash],
      interface: nil,
      wait_timeout: 540,
      wait_interval: 2.0,
      vm_customization: nil,
      guest_customization: nil,
      active_discovery: false,
      active_discovery_command: nil,
      vm_os: nil,
      vm_username: vm_username,
      vm_password: vm_password,
      vm_win_network: "Ethernet0",
      transform_ip: nil,
      benchmark: false,
      benchmark_file: "kitchen-vcenter.csv",
    }
  }
  let(:vm_name) { "my-vm-name" }
  let(:network_name) { "my-network" }
  let(:network_hash) { { name: "my-network", operation: "edit" } }
  let(:target_host) { instance_double("VSphereAutomation::VCenter::VcenterHostSummary", host: "host-123", name: "host-123.company.com", connection_state: "CONNECTED", power_state: "POWERED_ON") }
  let(:datacenter_name) { "my-datacenter" }
  let(:datacenter) { instance_double("RbVmomi::VIM::Datacenter", network: [network]) }
  let(:vm_username) { "vm-username" }
  let(:vm_password) { "vm-password" }

  let(:network) { instance_double("RbVmomi::VIM::DistributedVirtualPortgroup", name: network_name, pretty_path: "#{datacenter_name}/network/#{network_name}", config: network_config, key: "dvportgroup-123") }
  let(:network_config) { instance_double("RbVmomi::VIM::DVPortgroupConfigInfo", distributedVirtualSwitch: distributed_virtual_switch) }
  let(:distributed_virtual_switch) { instance_double("RbVmomi::VIM::VmwareDistributedVirtualSwitch", name: "dvs-123", uuid: SecureRandom.hex) }

  let(:rbvmomi_vim) { instance_double("RbVmomi::VIM", serviceContent: service_content, serviceInstance: service_instance) }
  let(:service_content) { instance_double("RbVmomi::ServiceContent", eventManager: event_manager ) }
  let(:event_manager) { instance_double("RbVmomi::EventManager") }
  let(:service_instance) { instance_double("RbVmomi::ServiceInstance", find_datacenter: datacenter, content: content) }
  let(:content) { instance_double("RbVmomi::ServiceInstance::Content", rootFolder: root_folder) }
  let(:root_folder) { instance_double("RbVmomi::ServiceInstance::Inv", findByInventoryPath: source_vm) }

  # Source VM
  let(:source_vm) { instance_double("RbVmomi::ServiceInstance::VM", config: source_vm_config, snapshot: nil) }
  let(:source_vm_config) { instance_double("RbVmomi::ServiceInstance::VM::Config", template: source_vm_template, guestId: "redhat", hardware: source_vm_hardware) }
  let(:source_vm_template) { instance_double("RbVmomi::ServiceInstance::VM::Template") }
  let(:source_vm_hardware) { instance_double("RbVmomi::VIM::VirtualHardware", device: [source_vm_network_device]) }
  let(:source_vm_network_device) { instance_double("RbVmomi::VIM::VirtualVmxnet3") }

  # Created VM
  let(:created_vm) { instance_double("RbVmomi::VIM::VirtualMachine", config: created_vm_config, snapshot: nil, guest: created_vm_guest, PowerOnVM_Task: created_vm_power_on_task) }
  let(:created_vm_config) { instance_double("RbVmomi::VIM::VirtualMachine", config: cloned_vm_config, snapshot: nil) }
  let(:created_vm_config) { instance_double("RbVmomi::ServiceInstance::VM::Config", guestId: "redhat", hardware: created_vm_hardware) }
  let(:created_vm_hardware) { instance_double("RbVmomi::VIM::VirtualHardware", device: [created_vm_network_device]) }
  let(:created_vm_network_device) { instance_double("RbVmomi::VIM::VirtualVmxnet3") }
  let(:created_vm_guest) { instance_double("VMGuest", toolsRunningStatus: "guestToolsRunning", net: [created_vm_guest_network]) }
  let(:created_vm_guest_network) { instance_double("RbVmomi::VIM::GuestNicInfo", ipConfig: created_vm_guest_ipconfig) }
  let(:created_vm_guest_ipconfig) { instance_double("RbVmomi::VIM::GuestIpConfig", ipAddress: [created_vm_guest_ipaddress]) }
  let(:created_vm_guest_ipaddress) { instance_double("RbVmomi::VIM::NetIpConfigInfoIpAddress", origin: "not_linklayer", ipAddress: "192.168.5.2") }
  let(:created_vm_power_on_task) { instance_double("VMPowerOnTask", wait_for_completion: nil) }
  let(:created_vm_reconfigure_task) { instance_double("VMReconfigureTask", wait_for_completion: nil) }
  let(:clone_vm_task) { instance_double("CloneVMTask") }

  before do
    allow(RbVmomi::VIM).to receive(:connect).with(connection_options).and_return(rbvmomi_vim)
    allow(RbVmomi::VIM).to receive(:NamePasswordAuthentication).with(interactiveSession: false, username: vm_username, password: vm_password)
    allow(service_instance).to receive(:find_datacenter).with(datacenter_name).and_return(datacenter)
    allow(network).to receive(:is_a?).with(RbVmomi::VIM::DistributedVirtualPortgroup).and_return(true)
    allow(source_vm_network_device).to receive(:is_a?).with(RbVmomi::VIM::VirtualEthernetCard).and_return(true)
    allow(source_vm_network_device).to receive(:backing=).with(
      RbVmomi::VIM.VirtualEthernetCardDistributedVirtualPortBackingInfo(
        port: RbVmomi::VIM.DistributedVirtualSwitchPortConnection(
          portgroupKey: network.key,
          switchUuid: distributed_virtual_switch.uuid
        )
      )
    )
    allow(source_vm).to receive(:CloneVM_Task).with(spec: anything, folder: folder_id, name: vm_name).and_return(clone_vm_task)
    allow(clone_vm_task).to receive(:wait_for_completion)
    allow(datacenter).to receive(:find_vm).with("#{folder_name}/#{vm_name}").and_return(created_vm)
    allow(Kitchen.logger).to receive(:info) # Do not show logs during unit tests
  end

  describe "#clone" do
    it "does not raise an exception" do
      expect { subject.clone }.not_to raise_error
    end

    context "when customization is not provided" do
      before do
        options[:vm_customization] = nil
      end

      it "does not reconfigure vm with custom config" do
        expect(created_vm).not_to receive(:ReconfigVM_Task)
        subject.clone
      end
    end

    context "when customization is provided" do
      let(:reconfigure_task) { instance_double("ReconfigureTask", wait_for_completion: nil) }

      before do
        options[:vm_customization] = {
          "someconfig" => "yeehaw",
        }
        allow(created_vm).to receive(:ReconfigVM_Task).with(spec: anything).and_return(created_vm_reconfigure_task)
      end

      it "reconfigures vm with custom config" do
        expect(RbVmomi::VIM).to receive(:VirtualMachineConfigSpec)
        expect(created_vm).to receive(:ReconfigVM_Task).and_return(created_vm_reconfigure_task)
        subject.clone
      end

      %i{annotation memoryMB numCPUs}.each do |param|
        context "when #{param} is provided" do
          before do
            options[:vm_customization] = {
              param => "value",
            }
          end

          it "includes #{param} in customization" do
            conf = {}
            conf[param.to_sym] = "value"
            expect(RbVmomi::VIM).to receive(:VirtualMachineConfigSpec).with(conf)

            subject.clone
          end
        end
      end

      context "when guestinfo.* is provided" do
        before do
          options[:vm_customization] = {
            "guestinfo.one" => "value",
          }
        end

        it "includes :customConfig in customization" do
          expect(RbVmomi::VIM).to receive(:VirtualMachineConfigSpec).with({ extraConfig: [{ key: "guestinfo.one", value: "value" }] })

          subject.clone
        end
      end

      context "when guestinfo.* is not provided" do
        before do
          options[:vm_customization] = {}
        end

        it "does not include :customConfig in customization" do
          expect(RbVmomi::VIM).to receive(:VirtualMachineConfigSpec).with({})

          subject.clone
        end
      end
    end

    context "attaching a new vm" do
      before do
        options[:network_name] = "my-network"

        allow(subject).to receive(:network_device).and_return(nil)
      end

      context "#attach_new_network?" do
        it "should return true" do
          expect(subject.attach_new_network?(nil)).to be_truthy
        end
      end

      it "should call the reconfig vm task to add vm" do
        expect(RbVmomi::VIM).to receive(:VirtualMachineConfigSpec)
        expect(created_vm).to receive(:ReconfigVM_Task).and_return(created_vm_reconfigure_task)
        expect(subject).to receive(:network_change_spec)

        subject.clone
      end
    end

    context "clone with multiple networks" do

      let(:network2) {
        instance_double(
          "RbVmomi::VIM::DistributedVirtualPortgroup",
          name: "my-network-2",
          pretty_path: "#{datacenter_name}/network/my-network-2",
          config: network_config, key: "dvportgroup-123"
        )
      }
      let(:network2_config) {
        instance_double(
          "RbVmomi::VIM::DVPortgroupConfigInfo",
          distributedVirtualSwitch: distributed_virtual_switch
        )
      }

      let(:datacenter) {
        instance_double("RbVmomi::VIM::Datacenter", network: [network, network2])
      }

      before(:each) do
        allow(network)
          .to receive(:is_a?)
          .with(RbVmomi::VIM::DistributedVirtualPortgroup)
          .and_return(true)

        allow(network2)
          .to receive(:is_a?)
          .with(RbVmomi::VIM::DistributedVirtualPortgroup)
          .and_return(true)

        options[:networks] = [network_hash, { name: "my-network-2", operation: "add" }]
        allow(created_vm).to receive(:ReconfigVM_Task).and_return(created_vm_reconfigure_task)
      end

      it "task should be successful" do
        expect { subject.clone }.not_to raise_error
      end

      it "network_change_spec should invoke twice" do
        expect(subject).to receive(:network_change_spec).twice

        subject.clone
      end

      it "helper method should return correct values" do
        expect(subject.add_network?).to be_truthy
        expect(subject.update_network?(network)).to be_truthy
        expect(subject.networks_to_update.first[:name]).to eq "my-network"
        expect(subject.networks_to_add.first[:name]).to eq "my-network-2"
      end
    end
  end
end
