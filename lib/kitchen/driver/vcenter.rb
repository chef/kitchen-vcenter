# frozen_string_literal: true
#
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

      # The main create method
      #
      # @param [Object] state is the state of the vm
      def create(state)
        save_and_validate_parameters
        connect

        # Using the clone class, create a machine for TK
        # Find the identifier for the targethost to pass to rbvmomi
        config[:targethost] = get_host(config[:targethost])

        # Use the root resource pool of a specified cluster, if any
        # @todo This does not allow to specify cluster AND pool yet
        unless config[:cluster].nil?
          cluster = get_cluster(config[:cluster])
          config[:resource_pool] = cluster.resource_pool
        else
          # Find the first resource pool on any cluster
          config[:resource_pool] = get_resource_pool(config[:resource_pool])
        end

        # Check that the datacenter exists
        datacenter_exists?(config[:datacenter])

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
          clone_type: config[:clone_type],
          network_name: config[:network_name],
          wait_timeout: config[:vm_wait_timeout],
          wait_interval: config[:vm_wait_interval],
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

        raise format("Cannot specify both cluster and resource_pool") if !config[:cluster].nil? && !config[:resource_pool].nil?
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
      def get_host(name)
        # create a host object to work with
        host_api = VSphereAutomation::VCenter::HostApi.new(api_client)

        if name.nil?
          hosts = host_api.list.value
        else
          hosts = host_api.list({ filter_names: name }).value
        end

        raise format("Unable to find target host: %s", name) if hosts.empty?

        hosts.first
      end

      # Gets the folder you want to create the VM
      #
      # @param [name] name is the name of the folder
      def get_folder(name)
        folder_api = VSphereAutomation::VCenter::FolderApi.new(api_client)
        folders = folder_api.list({ filter_names: name }).value

        raise format("Unable to find folder: %s", name) if folders.empty?

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

      # Gets the info of the cluster
      #
      # @param [name] name is the name of the Cluster
      def get_cluster(name)
        cluster_api = VSphereAutomation::VCenter::ClusterApi.new(api_client)
        clusters = cluster_api.list({ filter_names: name }).value

        raise format("Unable to find Cluster: %s", name) if clusters.empty?

        cluster_id = clusters.first.cluster

        host_api = VSphereAutomation::VCenter::HostApi.new(api_client)
        hosts = host_api.list({ filter_clusters: cluster_id, connection_states: "CONNECTED" }).value

        raise format("Unable to find active host in cluster %s", name) if hosts.empty?

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
          # Remove default pool for first pass (<= 1.2.1 behaviour to pick first user-defined pool found)
          resource_pools = rp_api.list.value.delete_if { |pool| pool.name == "Resources" }
          debug("Search of all resource pools found: " + resource_pools.map { |pool| pool.name }.to_s)

          # Revert to default pool, if no user-defined pool found (> 1.2.1 behaviour)
          # (This one might not be found under some circumstances by the statement above)
          return get_resource_pool("Resources") if resource_pools.empty?
        else
          resource_pools = rp_api.list({ filter_names: name }).value
          debug("Search for resource pools found: " + resource_pools.map { |pool| pool.name }.to_s)
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
