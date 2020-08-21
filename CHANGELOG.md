# Change Log

<!-- latest_release -->
<!-- latest_release -->
<!-- release_rollup -->
<!-- release_rollup -->

<!-- latest_stable_release -->
## [v2.7.12](https://github.com/chef/kitchen-vcenter/tree/v2.7.12) (2020-08-21)

#### Merged Pull Requests
- Update chefstyle requirement from 1.2.0 to 1.2.1 [#107](https://github.com/chef/kitchen-vcenter/pull/107) ([dependabot-preview[bot]](https://github.com/dependabot-preview[bot]))
- Allow folder to support nested paths [#108](https://github.com/chef/kitchen-vcenter/pull/108) ([cattywampus](https://github.com/cattywampus))
- Optimize our requires [#113](https://github.com/chef/kitchen-vcenter/pull/113) ([tas50](https://github.com/tas50))
<!-- latest_stable_release -->

## [v2.7.9](https://github.com/chef/kitchen-vcenter/tree/v2.7.9) (2020-08-06)

#### Merged Pull Requests
- Resolve Style/RedundantAssignment warning [#106](https://github.com/chef/kitchen-vcenter/pull/106) ([tas50](https://github.com/tas50))

## [v2.7.8](https://github.com/chef/kitchen-vcenter/tree/v2.7.8) (2020-07-31)

#### Merged Pull Requests
- Fix minor spelling mistakes [#104](https://github.com/chef/kitchen-vcenter/pull/104) ([tas50](https://github.com/tas50))
- Update rbvmomi requirement from &gt;= 1.11, &lt; 3.0 to &gt;= 1.11, &lt; 4.0 [#105](https://github.com/chef/kitchen-vcenter/pull/105) ([dependabot-preview[bot]](https://github.com/dependabot-preview[bot]))

## [v2.7.6](https://github.com/chef/kitchen-vcenter/tree/v2.7.6) (2020-07-23)

#### Merged Pull Requests
- Enable Guest OS customization [#97](https://github.com/chef/kitchen-vcenter/pull/97) ([mkennedy85](https://github.com/mkennedy85))
- Cleaning up a linting error [#103](https://github.com/chef/kitchen-vcenter/pull/103) ([tyler-ball](https://github.com/tyler-ball))

## [v2.7.4](https://github.com/chef/kitchen-vcenter/tree/v2.7.4) (2020-07-16)

#### Merged Pull Requests
- Support datacenters stored in folders [#98](https://github.com/chef/kitchen-vcenter/pull/98) ([clintoncwolfe](https://github.com/clintoncwolfe))
- Add chefstyle validation on each PR [#100](https://github.com/chef/kitchen-vcenter/pull/100) ([tas50](https://github.com/tas50))
- Cleanup the github templates and codeowners [#102](https://github.com/chef/kitchen-vcenter/pull/102) ([tas50](https://github.com/tas50))
- Drop support for Ruby 2.3 [#101](https://github.com/chef/kitchen-vcenter/pull/101) ([tas50](https://github.com/tas50))

## [v2.7.0](https://github.com/chef/kitchen-vcenter/tree/v2.7.0) (2020-04-14)

#### Merged Pull Requests
- Add ability to transform VM IP for 1:1 NAT environments [#92](https://github.com/chef/kitchen-vcenter/pull/92) ([tecracer-theinen](https://github.com/tecracer-theinen))

## [v2.6.5](https://github.com/chef/kitchen-vcenter/tree/v2.6.5) (2020-03-16)

#### Merged Pull Requests
- Fallback to datacenter lookup that requires less privileges [#82](https://github.com/chef/kitchen-vcenter/pull/82) ([jasonwbarnett](https://github.com/jasonwbarnett))

## [v2.6.4](https://github.com/chef/kitchen-vcenter/tree/v2.6.4) (2020-02-18)

#### Merged Pull Requests
- Fix reference to undefined variable in CloneError message [#90](https://github.com/chef/kitchen-vcenter/pull/90) ([cattywampus](https://github.com/cattywampus))
- Fix active discovery command [#89](https://github.com/chef/kitchen-vcenter/pull/89) ([leotaglia](https://github.com/leotaglia))

## [v2.6.2](https://github.com/chef/kitchen-vcenter/tree/v2.6.2) (2020-02-12)

#### Merged Pull Requests
- declare network_device var in the correct scope [#84](https://github.com/chef/kitchen-vcenter/pull/84) ([teknofire](https://github.com/teknofire))
- Remove unused savon dep and use require_relative [#85](https://github.com/chef/kitchen-vcenter/pull/85) ([tas50](https://github.com/tas50))

## [v2.6.0](https://github.com/chef/kitchen-vcenter/tree/v2.6.0) (2019-11-05)

#### Merged Pull Requests
- Update to allow for the new rbvmomi [#80](https://github.com/chef/kitchen-vcenter/pull/80) ([tas50](https://github.com/tas50))

## [v2.5.2](https://github.com/chef/kitchen-vcenter/tree/v2.5.2) (2019-09-16)

#### Merged Pull Requests
- Improve loose target host and folder filters [#73](https://github.com/chef/kitchen-vcenter/pull/73) ([sandratiffin](https://github.com/sandratiffin))
- Fix error if no clusters are defined or targethost is not a member [#75](https://github.com/chef/kitchen-vcenter/pull/75) ([tecracer-theinen](https://github.com/tecracer-theinen))
- Implement functionality to add disks to the cloned VM [#76](https://github.com/chef/kitchen-vcenter/pull/76) ([tecracer-theinen](https://github.com/tecracer-theinen))

## [v2.4.0](https://github.com/chef/kitchen-vcenter/tree/v2.4.0) (2019-06-19)

#### Merged Pull Requests
- Implement aggressive IP polling mode [#66](https://github.com/chef/kitchen-vcenter/pull/66) ([tecracer-theinen](https://github.com/tecracer-theinen))
- Improve and fix support for Instant Clones, add Benchmark option [#70](https://github.com/chef/kitchen-vcenter/pull/70) ([tecracer-theinen](https://github.com/tecracer-theinen))

## [v2.2.2](https://github.com/chef/kitchen-vcenter/tree/v2.2.2) (2019-03-20)

#### Merged Pull Requests
- Loosen the Test Kitchen dep to allow 2.X [#65](https://github.com/chef/kitchen-vcenter/pull/65) ([tas50](https://github.com/tas50))

## [v2.2.1](https://github.com/chef/kitchen-vcenter/tree/v2.2.1) (2019-03-04)

#### Merged Pull Requests
- Network Interface Selection Support [#63](https://github.com/chef/kitchen-vcenter/pull/63) ([tecracer-theinen](https://github.com/tecracer-theinen))
- Fix instant clones, which failed after implementing VM reconfiguration [#64](https://github.com/chef/kitchen-vcenter/pull/64) ([tecracer-theinen](https://github.com/tecracer-theinen))

## [v2.1.0](https://github.com/chef/kitchen-vcenter/tree/v2.1.0) (2019-02-27)

#### Merged Pull Requests
- Implement reconfiguration of VM memory/CPUs and other parameters [#61](https://github.com/chef/kitchen-vcenter/pull/61) ([tecracer-theinen](https://github.com/tecracer-theinen))
- Implement using both cluster/resource_pool [#62](https://github.com/chef/kitchen-vcenter/pull/62) ([tecracer-theinen](https://github.com/tecracer-theinen))

## [v2.0.2](https://github.com/chef/kitchen-vcenter/tree/v2.0.2) (2019-02-12)

#### Merged Pull Requests
- Implementation of configurable timeouts and automatic rollback (v2) [#58](https://github.com/chef/kitchen-vcenter/pull/58) ([tecracer-theinen](https://github.com/tecracer-theinen))

## [v2.0.1](https://github.com/chef/kitchen-vcenter/tree/v2.0.1) (2019-02-12)

#### Merged Pull Requests
- Add support for network_name to accept vSphere Distributed Switches [#60](https://github.com/chef/kitchen-vcenter/pull/60) ([tecracer-theinen](https://github.com/tecracer-theinen))

## [v2.0.0](https://github.com/chef/kitchen-vcenter/tree/v2.0.0) (2019-01-30)

- Bump the major version since we&#39;re using the rubygems published API now [#56](https://github.com/chef/kitchen-vcenter/pull/56) ([tas50](https://github.com/tas50)) <!-- 2.0.0 -->
- Migration to new openapi based SDK [#55](https://github.com/chef/kitchen-vcenter/pull/55) ([tecracer-theinen](https://github.com/tecracer-theinen)) <!-- 1.5.1 -->

## [v1.5.0](https://github.com/chef/kitchen-vcenter/tree/v1.5.0) (2019-01-12)

#### Merged Pull Requests
- Add ability to move the created VM onto another network via using the &quot;network_name&quot; parameter [#47](https://github.com/chef/kitchen-vcenter/pull/47) ([tecracer-theinen](https://github.com/tecracer-theinen))
- Fix destroy action [#50](https://github.com/chef/kitchen-vcenter/pull/50) ([tecracer-theinen](https://github.com/tecracer-theinen))
- Add feature to tag kitchen instances [#52](https://github.com/chef/kitchen-vcenter/pull/52) ([tecracer-theinen](https://github.com/tecracer-theinen))
- Allow template names to include a VM folder path [#48](https://github.com/chef/kitchen-vcenter/pull/48) ([tecracer-theinen](https://github.com/tecracer-theinen))
- Update the author of the gem to be Chef Software [#53](https://github.com/chef/kitchen-vcenter/pull/53) ([tas50](https://github.com/tas50))

## [v1.4.2](https://github.com/chef/kitchen-vcenter/tree/v1.4.2) (2019-01-04)

#### Merged Pull Requests
- Require Ruby 2.3+ and slim the files we ship in the gem [#45](https://github.com/chef/kitchen-vcenter/pull/45) ([tas50](https://github.com/tas50))
- Add support for provisioning on a specific cluster [#42](https://github.com/chef/kitchen-vcenter/pull/42) ([tecracer-theinen](https://github.com/tecracer-theinen))
- Add support for instant clones and documentation [#43](https://github.com/chef/kitchen-vcenter/pull/43) - Thank you [Siemens Gamesa](https://www.siemensgamesa.com) for sponsoring this contribution.

## [v1.3.4](https://github.com/chef/kitchen-vcenter/tree/v1.3.4) (2019-01-04)

#### Merged Pull Requests
- README edits [#38](https://github.com/chef/kitchen-vcenter/pull/38) ([mjingle](https://github.com/mjingle))
- Feature/check parameters [#40](https://github.com/chef/kitchen-vcenter/pull/40) ([tecracer-theinen](https://github.com/tecracer-theinen))
- Fix for Issues #26 and #30 [#44](https://github.com/chef/kitchen-vcenter/pull/44) ([tecracer-theinen](https://github.com/tecracer-theinen))

## [v1.3.1](https://github.com/chef/kitchen-vcenter/tree/v1.3.1) (2018-11-19)

#### Merged Pull Requests
- Fixed behaviour when not having any resource pools (Issue #28) [#31](https://github.com/chef/kitchen-vcenter/pull/31) ([tecracer-theinen](https://github.com/tecracer-theinen))
- Implement support for linked clones (feature #18) [#32](https://github.com/chef/kitchen-vcenter/pull/32) ([tecracer-theinen](https://github.com/tecracer-theinen))
- Chefstyle fixes [#37](https://github.com/chef/kitchen-vcenter/pull/37) ([tas50](https://github.com/tas50))

## [1.2.1](https://github.com/chef/kitchen-vcenter/tree/1.2.1) (2017-09-14)
[Full Changelog](https://github.com/chef/kitchen-vcenter/compare/v1.2.0...1.2.1)

**Closed issues:**

- Install attempt errors with message about requiring vsphere-automation-sdk [\#11](https://github.com/chef/kitchen-vcenter/issues/11)

**Merged pull requests:**

- Update dependency reqs. Update README for dep install. [\#12](https://github.com/chef/kitchen-vcenter/pull/12) ([akulbe](https://github.com/akulbe))

## [v1.2.0](https://github.com/chef/kitchen-vcenter/tree/v1.2.0) (2017-09-12)
[Full Changelog](https://github.com/chef/kitchen-vcenter/compare/v1.1.0...v1.2.0)

**Merged pull requests:**

- Resource pool and target host no longer have to be specified. [\#10](https://github.com/chef/kitchen-vcenter/pull/10) ([russellseymour](https://github.com/russellseymour))

## [v1.1.0](https://github.com/chef/kitchen-vcenter/tree/v1.1.0) (2017-09-07)
[Full Changelog](https://github.com/chef/kitchen-vcenter/compare/v1.0.0...v1.1.0)

**Closed issues:**

- Resource pool is not specified when creating a new machine [\#7](https://github.com/chef/kitchen-vcenter/issues/7)
- Unhelpful messages from driver if specified item does not exist [\#6](https://github.com/chef/kitchen-vcenter/issues/6)

**Merged pull requests:**

- Updated to handle resource\_pools [\#8](https://github.com/chef/kitchen-vcenter/pull/8) ([russellseymour](https://github.com/russellseymour))

## [v1.0.0](https://github.com/chef/kitchen-vcenter/tree/v1.0.0) (2017-08-28)
**Merged pull requests:**

- 1.0.0 release [\#4](https://github.com/chef/kitchen-vcenter/pull/4) ([jjasghar](https://github.com/jjasghar))
- Second walk through [\#3](https://github.com/chef/kitchen-vcenter/pull/3) ([jjasghar](https://github.com/jjasghar))
- Updated so that the vm\_name is set according to suite and platform. [\#2](https://github.com/chef/kitchen-vcenter/pull/2) ([russellseymour](https://github.com/russellseymour))
- Prep-for-public release [\#1](https://github.com/chef/kitchen-vcenter/pull/1) ([jjasghar](https://github.com/jjasghar))



\* *This Change Log was automatically generated by [github_changelog_generator](https://github.com/skywinder/Github-Changelog-Generator)*