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

require 'kitchen'
require 'rbvmomi'
require 'sso'
require 'base'
require 'lookup_service_helper'
require 'vapi'
require 'com/vmware/cis'
require 'com/vmware/vcenter'
require 'com/vmware/vcenter/vm'
require 'support/clone_vm'
require 'securerandom'

module Kitchen
  module Driver
    #
    # Vcenter
    #
    class Vcenter < Kitchen::Driver::Base
      attr_accessor :connection_options, :ipaddress, :vapi_config, :session_svc, :session_id

      default_config :targethost
      default_config :folder
      default_config :template
      default_config :datacenter
      default_config :vcenter_username
      default_config :vcenter_password
      default_config :vcenter_host
      default_config :vcenter_disable_ssl_verify, false
      default_config :poweron, true
      default_config :vm_name, nil

      def create(state)
        # If the vm_name has not been set then set it now based on the suite, platform and a random number
        if config[:vm_name].nil?
          config[:vm_name] = format('%s-%s-%s', instance.suite.name, instance.platform.name, SecureRandom.hex(4))
        end

        connect

        # Using the clone class, create a machine for TK
        # Find the identifier for the targethost to pass to rbvmomi
        config[:targethost] = get_host(config[:targethost])

        # Same thing needs to happen with the folder name if it has been set
        config[:folder] = {
          name: config[:folder],
          id: get_folder(config[:folder])
        } unless config[:folder].nil?

        # Create a hash of options that the clone requires
        options = {
          name: config[:vm_name],
          targethost: config[:targethost],
          poweron: config[:poweron],
          template: config[:template],
          datacenter: config[:datacenter],
          folder: config[:folder]
        }

        # Create an object from which the clone operation can be called
        clone_obj = Support::CloneVm.new(connection_options, options)
        state[:hostname] = clone_obj.clone()
        state[:vm_name] = config[:vm_name]
      end

      def destroy(state)
        return if state[:vm_name].nil?
        connect
        vm = get_vm(state[:vm_name])

        vm_obj = Com::Vmware::Vcenter::VM.new(vapi_config)

        # shut the machine down if it is running
        if vm.power_state.value == "POWERED_ON"
          power = Com::Vmware::Vcenter::Vm::Power.new(vapi_config)
          power.stop(vm.vm)
        end

        # delete the vm
        vm_obj.delete(vm.vm)
      end

      private

      def validate_state(state = {})

      end

      def existing_state_value?(state, property)
        state.key?(property) && !state[property].nil?
      end

      def get_host(name)
        filter = Com::Vmware::Vcenter::Host::FilterSpec.new({names: Set.new([name])})
        host_obj = Com::Vmware::Vcenter::Host.new(vapi_config)
        host = host_obj.list
        host[0].host
      end

      def get_folder(name)
        # Create a filter to ensure that only the named folder is returned
        filter = Com::Vmware::Vcenter::Folder::FilterSpec.new({names: Set.new([name])})
        # filter.names = name
        folder_obj = Com::Vmware::Vcenter::Folder.new(vapi_config)
        folder = folder_obj.list(filter)

        folder[0].folder
      end

      def get_vm(name)
        filter = Com::Vmware::Vcenter::VM::FilterSpec.new({names: Set.new([name])})
        vm_obj = Com::Vmware::Vcenter::VM.new(vapi_config)
        vm_obj.list(filter)[0]
      end

      def connect
        # Configure the connection to vCenter
        lookup_service_helper = LookupServiceHelper.new(config[:vcenter_host])
        vapi_urls = lookup_service_helper.find_vapi_urls()
        vapi_url = vapi_urls.values[0]

        # Create the VAPI config object
        ssl_options = {}
        ssl_options[:verify] = config[:vcenter_disable_ssl_verify] ? :none : :peer
        @vapi_config = VAPI::Bindings::VapiConfig.new(vapi_url, ssl_options)

        # get the SSO url
        sso_url = lookup_service_helper.find_sso_url()
        sso = SSO::Connection.new(sso_url).login(config[:vcenter_username], config[:vcenter_password])
        token = sso.request_bearer_token()
        vapi_config.set_security_context(
          VAPI::Security.create_saml_bearer_security_context(token.to_s)
        )

        # Login and get the session information
        @session_svc = Com::Vmware::Cis::Session.new(vapi_config)
        @session_id = session_svc.create()
        vapi_config.set_security_context(
          VAPI::Security.create_session_security_context(session_id)
        )

        # Configure the hash for use when connecting for cloning a machine
        @connection_options = {
          user: config[:vcenter_username],
          password: config[:vcenter_password],
          insecure: config[:vcenter_disable_ssl_verify] ? true : false,
          host: config[:vcenter_host],
        }
      end
    end
  end
end
