# Author:: Chef Partner Engineering (<partnereng@chef.io>)
# Copyright:: Copyright (c) 2017 Chef Software, Inc.
# License:: Apache License, Version 2.0
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

require "kitchen"
require "vsphere-automation-cis"
require "vsphere-automation-vcenter"
require "support/clone_vm"
require "securerandom"
require "uri"

# The main kitchen module
module Kitchen
  # The main driver module for kitchen-vcenter
  module Driver
    # Extends the Base class for vCenter
    class Vcenter < Kitchen::Driver::Base
      attr_accessor :connection_options, :ipaddress, :api_client

      required_config :vcenter_username
      required_config :vcenter_password
      required_config :vcenter_host
      required_config :datacenter
      required_config :template

      default_config :vcenter_disable_ssl_verify, false
      default_config :targethost, nil
      default_config :folder, nil
      default_config :poweron, true
      default_config :vm_name, nil
      default_config :resource_pool, nil
      default_config :clone_type, :full
      default_config :cluster, nil
      default_config :network_name, nil
      default_config :tags, nil
      default_config :vm_wait_timeout, 90
      default_config :vm_wait_interval, 2.0
      default_config :vm_rollback, false
      default_config :customize, nil
      default_config :interface, nil
      default_config :active_discovery, false
      default_config :active_discovery_command, nil
      default_config :vm_os, nil
      default_config :vm_username, "vagrant"
      default_config :vm_password, "vagrant"
      default_config :vm_win_network, "Ethernet0"

      default_config :benchmark, false
      default_config :benchmark_file, "kitchen-vcenter.csv"

      deprecate_config_for :aggressive_mode, Util.outdent!(<<-MSG)
        The 'aggressive_mode' setting was renamed to 'active_discovery' and
        will be removed in future versions
      MSG
      deprecate_config_for :aggressive_os, Util.outdent!(<<-MSG)
        The 'aggressive_os' setting was renamed to 'vm_os' and will be
        removed in future versions.
      MSG
      deprecate_config_for :aggressive_username, Util.outdent!(<<-MSG)
        The 'aggressive_username' setting was renamed to 'vm_username' and will
        be removed in future versions.
      MSG
      deprecate_config_for :aggressive_password, Util.outdent!(<<-MSG)
        The 'aggressive_password' setting was renamed to 'vm_password' and will
        be removed in future versions.
      MSG

      # The main create method
      #
      # @param [Object] state is the state of the vm
      def create(state)
        save_and_validate_parameters
        connect

        # Use the root resource pool of a specified cluster, if any
        if config[:cluster].nil?
          # Find the first resource pool on any cluster
          config[:resource_pool] = get_resource_pool(config[:resource_pool])
        else
          cluster = get_cluster(config[:cluster])
          root_pool = cluster.resource_pool

          if config[:resource_pool].nil?
            config[:resource_pool] = root_pool
          else
            rp_api = VSphereAutomation::VCenter::ResourcePoolApi.new(api_client)

            found_pool = nil
            pools = rp_api.get(root_pool).value.resource_pools
            pools.each do |pool|
              name = rp_api.get(pool).value.name
              found_pool = pool if name == config[:resource_pool]
            end

            raise format("Pool %s not found on cluster %s", config[:resource_pool], config[:cluster]) if found_pool.nil?

            config[:resource_pool] = found_pool
          end
        end

        # Check that the datacenter exists
        datacenter_exists?(config[:datacenter])

        # Get datacenter and cluster information
        datacenter = get_datacenter(config[:datacenter])
        cluster_id = get_cluster_id(config[:cluster])

        # Using the clone class, create a machine for TK
        # Find the identifier for the targethost to pass to rbvmomi
        config[:targethost] = get_host(config[:targethost], datacenter, cluster_id)

        # Check if network exists, if to be changed
        network_exists?(config[:network_name]) unless config[:network_name].nil?

        # Same thing needs to happen with the folder name if it has been set
        unless config[:folder].nil?
          config[:folder] = {
            name: config[:folder],
            id: get_folder(config[:folder]),
          }
        end

        # Allow different clone types
        config[:clone_type] = :linked if config[:clone_type] == "linked"
        config[:clone_type] = :instant if config[:clone_type] == "instant"

        # Create a hash of options that the clone requires
        options = {
          name: config[:vm_name],
          targethost: config[:targethost],
          poweron: config[:poweron],
          template: config[:template],
          datacenter: config[:datacenter],
          folder: config[:folder],
          resource_pool: config[:resource_pool],
          clone_type: config[:clone_type].to_sym,
          network_name: config[:network_name],
          interface: config[:interface],
          wait_timeout: config[:vm_wait_timeout],
          wait_interval: config[:vm_wait_interval],
          customize: config[:customize],
          active_discovery: config[:active_discovery],
          active_discovery_command: config[:active_discovery_command],
          vm_os: config[:vm_os],
          vm_username: config[:vm_username],
          vm_password: config[:vm_password],
          vm_win_network: config[:vm_win_network],
          benchmark: config[:benchmark],
          benchmark_file: config[:benchmark_file],
        }

        begin
          # Create an object from which the clone operation can be called
          new_vm = Support::CloneVm.new(connection_options, options)
          new_vm.clone

          state[:hostname] = new_vm.ip
          state[:vm_name] = new_vm.name

        rescue # Kitchen::ActionFailed => e
          if config[:vm_rollback] == true
            error format("Rolling back VM %s after critical error", config[:vm_name])

            # Inject name of failed VM for destroy to work
            state[:vm_name] = config[:vm_name]

            destroy(state)
          end

          raise
        end

        unless config[:tags].nil? || config[:tags].empty?
          tag_api = VSphereAutomation::CIS::TaggingTagApi.new(api_client)
          vm_tags = tag_api.list.value
          raise format("No configured tags found on VCenter, but %s specified", config[:tags].to_s) if vm_tags.empty?

          valid_tags = {}
          vm_tags.each do |uid|
            tag = tag_api.get(uid)

            valid_tags[tag.value.name] = tag.value.id if tag.is_a? VSphereAutomation::CIS::CisTaggingTagResult
          end

          # Error out on undefined tags
          invalid = config[:tags] - valid_tags.keys
          raise format("Specified tag(s) %s not valid", invalid.join(",")) unless invalid.empty?

          tag_service = VSphereAutomation::CIS::TaggingTagAssociationApi.new(api_client)
          tag_ids = config[:tags].map { |name| valid_tags[name] }

          request_body = {
            object_id: {
              id: get_vm(config[:vm_name]).vm,
              type: "VirtualMachine",
            },
            tag_ids: tag_ids,
          }
          tag_service.attach_multiple_tags_to_object(request_body)
        end
      end

      # The main destroy method
      #
      # @param [Object] state is the state of the vm
      def destroy(state)
        return if state[:vm_name].nil?

        # Reset resource pool, as it's not needed for the destroy action but might be a remnant of earlier calls to "connect"
        # Temporary fix until setting cluster + resource_pool at the same time is implemented (lines #64/#187)
        config[:resource_pool] = nil

        save_and_validate_parameters
        connect

        vm = get_vm(state[:vm_name])
        unless vm.nil?
          vm_api = VSphereAutomation::VCenter::VMApi.new(api_client)

          # shut the machine down if it is running
          if vm.power_state == "POWERED_ON"
            power = VSphereAutomation::VCenter::VmPowerApi.new(api_client)
            power.stop(vm.vm)
          end

          # delete the vm
          vm_api.delete(vm.vm)
        end
      end

      private

      # Helper method for storing and validating configuration parameters
      #
      def save_and_validate_parameters
        # Configure the hash for use when connecting for cloning a machine
        @connection_options = {
          user: config[:vcenter_username],
          password: config[:vcenter_password],
          insecure: config[:vcenter_disable_ssl_verify] ? true : false,
          host: config[:vcenter_host],
          rev: config[:clone_type] == "instant" ? "6.7" : nil,
        }

        # If the vm_name has not been set then set it now based on the suite, platform and a random number
        if config[:vm_name].nil?
          config[:vm_name] = format("%s-%s-%s", instance.suite.name, instance.platform.name, SecureRandom.hex(4))
        end

        # See details in function get_resource_pool for more details
        # if config[:cluster].nil? && config[:resource_pool].nil?
        #   warn("It is recommended to specify cluster and/or resource_pool to avoid unpredictable machine placement on large deployments")
        # end

        # Process deprecated parameters
        config[:active_discovery] = config[:aggressive_mode] unless config[:aggressive_mode].nil?
        config[:vm_os] = config[:aggressive_os] unless config[:aggressive_os].nil?
        config[:vm_username] = config[:aggressive_username] unless config[:aggressive_username].nil?
        config[:vm_password] = config[:aggressive_password] unless config[:aggressive_password].nil?
      end

      # A helper method to validate the state
      #
      # @param [Object] state is the state of the vm
      def validate_state(state = {}); end

      def existing_state_value?(state, property)
        state.key?(property) && !state[property].nil?
      end

      # Sees in the datacenter exists or not
      #
      # @param [name] name is the name of the datacenter
      def datacenter_exists?(name)
        dc_api = VSphereAutomation::VCenter::DatacenterApi.new(api_client)
        dcs = dc_api.list({ filter_names: name }).value

        raise format("Unable to find data center: %s", name) if dcs.empty?
      end

      # Checks if a network exists or not
      #
      # @param [name] name is the name of the Network
      def network_exists?(name)
        net_api = VSphereAutomation::VCenter::NetworkApi.new(api_client)
        nets = net_api.list({ filter_names: name }).value

        raise format("Unable to find target network: %s", name) if nets.empty?
      end

      # Validates the host name of the server you can connect to
      #
      # @param [name] name is the name of the host
      def get_host(name, datacenter, cluster)
        # create a host object to work with
        host_api = VSphereAutomation::VCenter::HostApi.new(api_client)

        hosts = host_api.list({ filter_names: name,
                                filter_datacenters: datacenter,
                                filter_clusters: cluster,
                                filter_connection_states: ["CONNECTED"] }).value

        raise format("Unable to find target host: %s", name) if hosts.empty?

        hosts.sample
      end

      # Gets the folder you want to create the VM
      #
      # @param [name] name is the name of the folder
      def get_folder(name)
        folder_api = VSphereAutomation::VCenter::FolderApi.new(api_client)
        folders = folder_api.list({ filter_names: name, filter_type: "VIRTUAL_MACHINE" }).value

        raise format("Unable to find folder: %s", name) if folders.empty?

        raise format("%s returned too many folders", name) if folders.length > 1

        folders.first.folder
      end

      # Gets the name of the VM you are creating
      #
      # @param [name] name is the name of the VM
      def get_vm(name)
        vm_api = VSphereAutomation::VCenter::VMApi.new(api_client)
        vms = vm_api.list({ filter_names: name }).value

        vms.first
      end

      # Gets the info of the datacenter
      #
      # @param [name] name is the name of the Datacenter
      def get_datacenter(name)
        dc_api = VSphereAutomation::VCenter::DatacenterApi.new(api_client)
        dcs = dc_api.list({ filter_names: name }).value

        raise format("Unable to find data center: %s", name) if dcs.empty?

        raise format("%s returned too many data centers", name) if dcs.length > 1

        dcs.first.datacenter
      end

      # Gets the ID of the cluster
      #
      # @param [name] name is the name of the Cluster
      def get_cluster_id(name)
        cluster_api = VSphereAutomation::VCenter::ClusterApi.new(api_client)
        clusters = cluster_api.list({ filter_names: name }).value

        raise format("Unable to find Cluster: %s", name) if clusters.empty?

        raise format("%s returned too many clusters", name) if clusters.length > 1

        clusters.first.cluster
      end

      # Gets the info of the cluster
      #
      # @param [name] name is the name of the Cluster
      def get_cluster(name)
        cluster_id = get_cluster_id(name)

        host_api = VSphereAutomation::VCenter::HostApi.new(api_client)
        hosts = host_api.list({ filter_clusters: cluster_id, connection_states: "CONNECTED" }).value

        raise format("Unable to find active host in cluster %s", name) if hosts.empty?

        cluster_api = VSphereAutomation::VCenter::ClusterApi.new(api_client)
        cluster_api.get(cluster_id).value
      end

      # Gets the name of the resource pool
      #
      # @todo Will not yet work with nested pools ("Pool1/Subpool1")
      # @param [name] name is the name of the ResourcePool
      def get_resource_pool(name)
        # Create a resource pool object
        rp_api = VSphereAutomation::VCenter::ResourcePoolApi.new(api_client)

        # If no name has been set, use the first resource pool that can be found,
        # otherwise try to find by given name
        if name.nil?
          # Unpredictable results can occur, if neither cluster nor resource_pool are specified,
          # as this relies on the order in which VMware saves the objects. This does not have large
          # impact on small environments, but on large deployments with lots of clusters and pools,
          # provisioned machines are likely to "jump around" available hosts.
          #
          # This behaviour is carried on from versions 1.2.1 and lower, but likely to be removed in
          # a new major version due to these insufficiencies and the confusing code for it

          # Remove default pool for first pass (<= 1.2.1 behaviour to pick first user-defined pool found)
          resource_pools = rp_api.list.value.delete_if { |pool| pool.name == "Resources" }
          debug("Search of all resource pools found: " + resource_pools.map(&:name).to_s)

          # Revert to default pool, if no user-defined pool found (> 1.2.1 behaviour)
          # (This one might not be found under some circumstances by the statement above)
          return get_resource_pool("Resources") if resource_pools.empty?
        else
          resource_pools = rp_api.list({ filter_names: name }).value
          debug("Search for resource pools found: " + resource_pools.map(&:name).to_s)
        end

        raise format("Unable to find Resource Pool: %s", name) if resource_pools.empty?

        resource_pools.first.resource_pool
      end

      # The main connect method
      #
      def connect
        configuration = VSphereAutomation::Configuration.new.tap do |c|
          c.host = config[:vcenter_host]
          c.username = config[:vcenter_username]
          c.password = config[:vcenter_password]
          c.scheme = "https"
          c.verify_ssl = config[:vcenter_disable_ssl_verify] ? false : true
          c.verify_ssl_host = config[:vcenter_disable_ssl_verify] ? false : true
        end

        @api_client = VSphereAutomation::ApiClient.new(configuration)
        api_client.default_headers["Authorization"] = configuration.basic_auth_token

        session_api = VSphereAutomation::CIS::SessionApi.new(api_client)
        session_id = session_api.create("").value

        api_client.default_headers["vmware-api-session-id"] = session_id
      end
    end
  end
end
