lib = File.expand_path("lib", __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

require "kitchen-vcenter/version"

Gem::Specification.new do |spec|
  spec.name          = "kitchen-vcenter"
  spec.version       = KitchenVcenter::VERSION
  spec.authors       = ["Chef Software"]
  spec.email         = ["oss@chef.io"]
  spec.summary       = "Test Kitchen driver for VMware vCenter"
  spec.description   = "Test Kitchen driver for VMware vCenter using SDK"
  spec.homepage      = "https://github.com/chef/kitchen-vcenter"
  spec.license       = "Apache-2.0"

  spec.files         = Dir["LICENSE", "lib/**/*"]
  spec.require_paths = ["lib"]

  spec.required_ruby_version = ">= 2.5"

  spec.add_dependency "net-ping", ">= 2.0.0", "< 3.0"
  spec.add_dependency "rbvmomi", ">= 1.11", "< 4.0"
  spec.add_dependency "test-kitchen", ">= 1.16", "< 4"
  spec.add_dependency "vsphere-automation-sdk", "~> 0.4"
end
