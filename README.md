# kitchen-vcenter

[![Gem Version](https://badge.fury.io/rb/kitchen-vcenter.svg)](https://rubygems.org/gems/kitchen-vcenter)
[![Build status](https://badge.buildkite.com/4b0ca1bb5cd02dee51d9ce789f8346eb05730685c5be7fbba9.svg?branch=master)](https://buildkite.com/chef-oss/chef-kitchen-vcenter-master-verify)

This is the official Chef test-kitchen plugin for VMware REST API. This plugin gives kitchen the ability to create, bootstrap, and test VMware vms.

- Documentation: [https://github.com/chef/kitchen-vcenter/blob/master/README.md](https://github.com/chef/kitchen-vcenter/blob/master/README.md)
- Source: [https://github.com/chef/kitchen-vcenter/tree/master](https://github.com/chef/kitchen-vcenter/tree/master)
- Issues: [https://github.com/chef/kitchen-vcenter/issues](https://github.com/chef/knife-vcenter/issues)
- Mailing list: [https://discourse.chef.io/](https://discourse.chef.io/)

This is a `test-kitchen` plugin that allows interaction with vSphere using the vSphere Automation SDK.

Please refer to the [CHANGELOG](CHANGELOG.md) for version history and known issues.

## Requirements

- Ruby 2.6 or higher
- VMware vCenter/vSphere 5.5 or higher
- VMs or templates to clone, with open-vm-tools installed
- DHCP server to assign IPs to kitchen instances

## Installation

The kitchen-vcenter driver ships as part of Chef Workstation. The easiest way to use this driver is to [Download Chef Workstation](https://www.chef.io/downloads/tools/workstation).

If you want to install the driver directly into a Ruby installation:

```sh
gem install kitchen-vcenter
```

If you're using Bundler, simply add it to your Gemfile:

```ruby
gem "kitchen-vcenter"
```

... and then run `bundle install`.

## Configuration

See the [kitchen.ci vCenter Driver Page](https://kitchen.ci/docs/drivers/vcenter/) for documentation on configuring this driver.

## Contributing

For information on contributing to this project see <https://github.com/chef/chef/blob/master/CONTRIBUTING.md>

## Development

* Report issues/questions/feature requests on [GitHub Issues][issues]

Pull requests are very welcome! Make sure your patches are well tested. Ideally create a topic branch for every separate change you make. For example:

1. Fork the repo
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Run the tests and chefstyle, `bundle exec rake spec` and `bundle exec rake style`
4. Commit your changes (`git commit -am 'Added some feature'`)
5. Push to the branch (`git push origin my-new-feature`)
6. Create new Pull Request

## License

- Author:: Russell Seymour ([rseymour@chef.io](mailto:rseymour@chef.io))
- Author:: JJ Asghar ([jj@chef.io](mailto:jj@chef.io))
- Author:: Thomas Heinen ([theinen@tecracer.de](mailto:theinen@tecracer.de))
- Author:: Michael Kennedy ([michael_l_kennedy@me.com](mailto:michael_l_kennedy@me.com))

Copyright:: Copyright (c) 2017-2022 Chef Software, Inc.

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
