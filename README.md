# kitchen-vcenter

[![Gem Version](https://badge.fury.io/rb/kitchen-vcenter.svg)](https://rubygems.org/gems/kitchen-vcenter)
[![Build Status](https://travis-ci.org/chef/kitchen-vcenter.svg?branch=master)](https://travis-ci.org/chef/kitchen-vcenter)
[![Inline docs](http://inch-ci.org/github/chef/kitchen-vcenter.svg?branch=master)](http://inch-ci.org/github/chef/kitchen-vcenter)

This is the official Chef test-kitchen plugin for VMware REST API. This plugin gives kitchen the ability to create, bootstrap, and test VMware vms.

- Documentation: [https://github.com/chef/kitchen-vcenter/blob/master/README.md](https://github.com/chef/kitchen-vcenter/blob/master/README.md)
- Source: [https://github.com/chef/kitchen-vcenter/tree/master](https://github.com/chef/kitchen-vcenter/tree/master)
- Issues: [https://github.com/chef/kitchen-vcenter/issues](https://github.com/chef/knife-vcenter/issues)
- Slack: sign up: https://code.vmware.com/slack/ slack channel: #chef
- Mailing list: [https://discourse.chef.io/](https://discourse.chef.io/)

This is a `test-kitchen` plugin that allows interaction with vSphere using the vSphere Automation SDK.

Please refer to the [CHANGELOG](CHANGELOG.md) for version history and known issues.

## Requirements

- Chef 13.0 higher
- Ruby 2.3.3 or higher
- VMware vCenter/vSphere 5.5 or higher
- VMs or templates to clone, with open-vm-tools installed
- DHCP server to assign IPs to kitchen instances

## Installation

Using [ChefDK](https://downloads.chef.io/chef-dk/), simply install the Gem:

```bash
chef gem install kitchen-vcenter
```

If you're using bundler, simply add Chef and kitchen-vcenter to your Gemfile:

```ruby
gem 'chef'
gem 'kitchen-vcenter'
```

## Usage

A sample `.kitchen.yml` file, details are below.

```yml
---
driver:
  name: vcenter
  vcenter_username: 'administrator@vsphere.local'
  vcenter_password: <%= ENV['VCENTER_PASSWORD'] %>
  vcenter_host:  <%= ENV['VCENTER_HOST'] %>
  vcenter_disable_ssl_verify: true
  customize:
    annotation: "Kitchen VM by <%= ENV['USER'] %> on <%= Time.now.to_s %>"

provisioner:
  name: chef_zero
  sudo_command: sudo
  deprecations_as_errors: true
  retry_on_exit_code:
    - 35 # 35 is the exit code signaling that the node is rebooting
  max_retries: 2
  wait_for_retry: 90

verifier:
  name: inspec

platforms:
  - name: ubuntu-1604
    driver:
      targethost: 10.0.0.42
      template: ubuntu16-template
      interface: "VM Network"
      datacenter: "Datacenter"
    transport:
      username: "admini"
      password: admini

  - name: centos-7
    driver:
      targethost: 10.0.0.42
      template: centos7-template
      datacenter: "Datacenter"
    transport:
      username: "root"
      password: admini

  - name: windows2012R2
    driver:
      targethost: 10.0.0.42
      network_name: "Internal"
      template: folder/windows2012R2-template
      datacenter: "Datacenter"
      customize:
        numCPUs: 4
        memoryMB: 1024
    transport:
      username: "Administrator"
      password: "p@ssW0rd!"

suites:
  - name: default
    run_list:
      - recipe[cookbook::default]
```

### Required parameters:

The following parameters should be set in the main `driver` section as they are common to all platforms:

 - `vcenter_username` - Name to use when connecting to the vSphere environment
 - `vcenter_password` - Password associated with the specified user
 - `vcenter_host` - Host against which logins should be attempted

The following parameters should be set in the `driver` section for the individual platform:

 - `datacenter` - Name of the datacenter to use to deploy into
 - `template` - Template or virtual machine to use when cloning the new machine (needs to be a VM for linked clones)

### Optional Parameters

The following parameters should be set in the main `driver` section as they are common to all platforms:
 - `vcenter_disable_ssl_verify` - Whether or not to disable SSL verification checks. Good when using self signed certificates. Default: false
 - `vm_wait_timeout` - Number of seconds to wait for VM connectivity. Default: 90
 - `vm_wait_interval` - Check interval between tries on VM connectivity. Default: 2.0
 - `vm_rollback` - Automatic roll back (destroy) of VMs failing the connectivity check. Default: false
 - `benchmark` - Write benchmark data for comparisons. Default: false
 - `benchmark_file` - Filename to write CSV data to. Default: "kitchen-vcenter.csv"

The following optional parameters should be used in the `driver` for the platform.

 - `resource_pool` - Name of the resource pool to use when creating the machine. Default: first pool
 - `cluster` - Cluster on which the new virtual machine should be created. Default: cluster of the `targethost` machine.
 - `targethost` - Host on which the new virtual machine should be created. If not specified then the first host in the cluster is used.
 - `folder` - Folder into which the new machine should be stored. If specified the folder _must_ already exist.
 - `poweron` - Power on the new virtual machine. Default: true
 - `vm_name` - Specify name of virtual machine. Default: `<suite>-<platform>-<random-hexid>`
 - `clone_type` - Type of clone, use "full" to create complete copies of template. Values: "full", "linked", "instant". Default: "full"
 - `network_name` - Network to reconfigure the first interface to, needs a VM Network name. Default: do not change
 - `tags` - Array of pre-defined vCenter tag names to assign (VMware tags are not key/value pairs). Default: none
 - `customize` - Dictionary of `xsd:*`-type customizations like annotation, memoryMB or numCPUs (see
[VirtualMachineConfigSpec](https://pubs.vmware.com/vsphere-6-5/index.jsp?topic=%2Fcom.vmware.wssdk.smssdk.doc%2Fvim.vm.ConfigSpec.html)). Default: none
 - `interface`- VM Network name to use for kitchen connections. Default: not set = first interface with usable IP

 The following optional parameters are relevant for active IP discovery.

 - `active_discovery` - Use active IP retrieval to speed up provisioning. Default: false
 - `active_discovery_command` - String or list of specific commands to retrieve VM IP (see Active Discovery Mode section below)
 - `vm_os` - OS family of the VM . Values: "linux", "windows". Default: autodetect from VMware
 - `vm_username` - Username to access the VM. Default: "vagrant"
 - `vm_password` - Password to access the VM. Default: "vagrant"

In addition to active IP discovery, the following optional parameter is relevant for instant clones using Windows.

 - `vm_win_network` - Internal Windows name of the Kitchen network adapter for reloading. Default: Ethernet0

## Clone types

### Clone type: full

This takes a VM or template, copies the whole disk and then boots up the machine. Default mode of operation.

Required prilveges:
- Datastore.AllocateSpace
- Network.Assign
- Resource.AssignVMToPool
- VirtualMachine.Interact.PowerOn
- VirtualMachine.Provisioning.Clone
- VirtualMachine.Provisioning.DeployTemplate

- VirtualMachine.Config.Annotation (depending on `customize` parameters)
- VirtualMachine.Config.CPUCount (depending on `customize` parameters)
- VirtualMachine.Config.Memory (depending on `customize` parameters)
- VirtualMachine.Config.EditDevice (if `network_name` is used)
- DVSwitch.CanUse (if `network_name is used with dVS/lVS)
- DVPortgroup.CanUse (if `network_name is used with dVS/lVS)

### Clone mode: linked

Instead of a full copy, "linked" uses delta disks to speed up the cloning process and uses many fewer IO operations. After creation of the delta disks, the machine is booted up and writes only to its delta disks.

The `template` parameter has to reference a VM (a template will not work) and a snapshot must be present. Otherwise, the driver will fall back to creating a full clone.

Depending on the underlying storage system, performance may vary greatly compared to full clones.

Required prilveges: (see "Clone mode: full")

### Clone mode: instant

The instant clone feature has been available under the name "VMFork" in earlier vSphere versions, but without a proper public API. With version 6.7.0, instant clones became an official feature. They work by not only using a delta disk like linked clones, but also share memory with the source machine. Because of sharing memory contents, the new machines are already booted up after cloning.

Prerequisites:
- vCenter version 6.7.0 or higher
- vSphere Hypervisor (aka ESXi) version 6.7.0 or higher
- VMware Tools installed and running
- a running source virtual machine (`template` parameter)
- for Linux, currently only `dhclient` is supported as DHCP client

Limitations:
- A new VM is always on the same host because of memory sharing
- The current driver supports only the "Frozen Source VM" workflow, which is more efficient than the "Running Source VM" version

Freezing the source VM:
- Login to the machine
- Execute the freeze operation, for example via `vmtoolsd --cmd "instantclone.freeze"`
- The machine does not execute any CPU instructions after this point

New clones resume from exactly the frozen point in time and also resume CPU activity automatically. The OS level network adapters get rescanned automatically
to pick up MAC address changes, which requires the privileges to use the Guest Operations API and login credentials (`vm_username`/`vm_password`).

Architectural description see <https://www.virtuallyghetto.com/2018/04/new-instant-clone-architecture-in-vsphere-6-7-part-1.html>

Needed privileges in addition to "Clone mode: full":
- VirtualMachine.Config.EditDevice
- VirtualMachine.Inventory.CreateFromExisting
- VirtualMachine.GuestOperations.Execute
- VirtualMachine.GuestOperations.Query

## Active Discovery Mode

This mode is used to speed up provisioning of kitchen machines as much as possible. One of the limiting factors despite actual provisioning time
(which can be improved using the linked/instant clone modes) is waiting for the VM to return its IP address. While VMware tools are usually available and
responding within 10-20 seconds, sending back IP/OS information to vCenter can take additional 30-40 seconds easily.

Active mode invokes OS specific commands for IP retrieval as soon as the VMware Tools are responding, by using the Guest Operations Manager
feature within the tools agent. Depending on the OS, a command to determine the IP will be executed using Bash (Linux) or CMD (Windows) and the
resulting output parsed. While the driver has sensible default commands, you can set your own via the `active_discovery_command` directive on the
platform level.

Active mode can speed up tests and pipelines by up to 30 seconds, but may fail due to asynchronous OS interaction in some instances. If retrieving the IP
fails for some reason, the VMware Tools provided data is used as fallback.

Needed privileges:
- VirtualMachine.GuestOperations.Execute
- VirtualMachine.GuestOperations.Query

Linux default:
`ip address show scope global | grep global | cut -b10- | cut -d/ -f1`

Windows default:
`sleep 5 & ipconfig`

## Benchmarking

To get some insight into the performance of your environment with different configurations, some simple benchmark functionality was built in. When you
enable this via the `benchmark` property, data gets appended to a CSV file (`benchmark_file` property) and printed to standard out (`-l debug` on CLI)

This file includes a header line describing the different fields such as the value of `template`, `clone_type` and `active_discovery` plus the different
steps within cloning a VM. The timing of steps is relative to each other and followed by a column with the total number of seconds for the whole cloning
operation.

## Contributing

For information on contributing to this project see <https://github.com/chef/chef/blob/master/CONTRIBUTING.md>

## Development

* Report issues/questions/feature requests on [GitHub Issues][issues]

Pull requests are very welcome! Make sure your patches are well tested. Ideally create a topic branch for every separate change you make. For example:

1. Fork the repo
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Run the tests and rubocop, `bundle exec rake spec` and `bundle exec rake rubocop`
4. Commit your changes (`git commit -am 'Added some feature'`)
5. Push to the branch (`git push origin my-new-feature`)
6. Create new Pull Request


## License

Author:: Russell Seymour ([rseymour@chef.io](mailto:rseymour@chef.io))
Author:: JJ Asghar ([jj@chef.io](mailto:jj@chef.io))
Author:: Thomas Heinen ([theinen@tecracer.de](mailto:theinen@tecracer.de))

Copyright:: Copyright (c) 2017-2019 Chef Software, Inc.

License:: Apache License, Version 2.0

```text
Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
```

[issues]: https://github.com/chef/kitchen-vcenter/issues
