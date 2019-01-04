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

## Installation

This driver has a dependency. It requires the [vSphere Automation SDK](https://github.com/vmware/vsphere-automation-sdk-ruby) be installed. The steps to do that are as follows, for the time being it's not published to Rubygems. If you are interested, please comment [here](https://github.com/vmware/vsphere-automation-sdk-ruby/issues/10).

- `$ git clone` [https://github.com/vmware/vsphere-automation-sdk-ruby.git](https://github.com/vmware/vsphere-automation-sdk-ruby.git)
- `cd vsphere-automation-sdk-ruby`
- `gem build vsphere-automation-sdk-ruby.gemspec`
- `chef gem install vsphere-automation-sdk-<version>.gem`

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
    driver_config:
      targethost: 10.0.0.42
      template: ubuntu16-template
      datacenter: "Datacenter"
    transport:
      username: "admini"
      password: admini

  - name: centos-7
    driver_config:
      targethost: 10.0.0.42
      template: centos7-template
      datacenter: "Datacenter"
    transport:
      username: "root"
      password: admini

  - name: windows2012R2
    driver_config:
      targethost: 10.0.0.42
      template: windows2012R2-template
      datacenter: "Datacenter"
    transport:
      username: "Administrator"
      password: "p@ssW0rd!"

suites:
  - name: default
    run_list:
      - recipe[cookbook::default]
```

### Required parameters:

The following parameters should be set in the main `driver_config` section as they are common to all platforms:

 - `vcenter_username` - Name to use when connecting to the vSphere environment
 - `vcenter_password` - Password associated with the specified user
 - `vcenter_host` - Host against which logins should be attempted

The following parameters should be set in the `driver_config` for the individual platform:

 - `datacenter` - Name of the datacenter to use to deploy into
 - `template` - Template or virtual machine to use when cloning the new machine (needs to be a VM for linked clones)

### Optional Parameters

The following parameters should be set in the main `driver_config` section as they are common to all platforms:
 - `vcenter_disable_ssl_verify` - Whether or not to disable SSL verification checks. Good when using self signed certificates. Default: false

The following optional parameters should be used in the `driver_config` for the platform.

 - `targethost` - Host on which the new virtual machine should be created. If not specified then the first host in the cluster is used.
 - `folder` - Folder into which the new machine should be stored. If specified the folder _must_ already exist.
 - `poweron` - Power on the new virtual machine. Default: true
 - `vm_name` - Specify name of virtual machine. Default: `<suite>-<platform>-<random-hexid>`
 - `clone_type` - Type of clone, use "full" to create complete copies of template. Values: "full", "linked", "instant". Default: "full"
 - `lookup_service_host` - Specify hostname of Lookup Service for setups with external PSC. Default: autodetect

Only one of the following optional parameters can be given:
 - `resource_pool` - Name of the resource pool to use when creating the machine. Default: first pool
 - `cluster` - Cluster on which the new virtual machine should be created. Default: cluster of the `targethost` machine.

## Clone types

### Clone type: full

This takes a VM or template, copies the whole disk and then boots up the machine. Default mode of operation.

### Clone mode: linked

Instead of a full copy, "linked" uses delta disks to speed up the cloning process and uses many fewer IO operations. The `template` parameter has to reference a VM in this case, a template will not work. After creation of the delta disks, the machine is booted up and writes only to its delta disks.

Depending on the underlying storage system, performance may vary greatly compared to full clones.

### Clone mode: instant

The instant clone feature has been available under the name "VMFork" in earlier vSphere versions, but without a proper public API. With version 6.7.0, instant clones became an official feature. They work by not only using a delta disk like linked clones, but also share memory with the source machine. Because of sharing memory contents, the new machines are already booted up after cloning.

Prerequisites:
- vCenter version 6.7.0 or higher
- vSphere Hypervisor (aka ESXi) version 6.7.0 or higher
- VMware Tools installed and running
- a running source virtual machine (`template` parameter)

Limitations:
- A new VM is always on the same host because of memory sharing
- The current driver supports only the "Frozen Source VM" workflow, which is more efficient than the "Running Source VM" version

Freezing the source VM:
- Login to the machine
- Execute the freeze operation, for example via `vmtoolsd -cmd "instantclone.freeze"`
- The machine does not execute any CPU instructions after this point

New clones resume from exactly the frozen point in time and also resume CPU activity automatically. In contrast to some early blog posts, they do not
duplicate the source MAC address, but get a different one.

Architectural description see <https://www.virtuallyghetto.com/2018/04/new-instant-clone-architecture-in-vsphere-6-7-part-1.html>

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

Copyright:: Copyright (c) 2017-2018 Chef Software, Inc.

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
