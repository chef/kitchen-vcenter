lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

require 'kitchen-vcenter/version'

Gem::Specification.new do |spec|
  spec.name          = 'kitchen-vcenter'
  spec.version       = KitchenVcenter::VERSION
  spec.authors       = ['Russell Seymour']
  spec.email         = ['russell@chef.io']
  spec.summary       = 'Test Kitchen driver for VMare vCenter'
  spec.description   = 'Test Kitchen driver for VMware vCenter using SDK'
  spec.homepage      = 'https://github.com/chef/kitchen-vcenter'
  spec.license       = 'Apache-2.0'

  spec.files         = Dir['LICENSE', 'README.md', 'CHANGELOG.md', 'lib/**/*', 'kitchen-vcenter/version.rb']
  spec.require_paths = ['lib']

  spec.add_dependency 'test-kitchen', '= 1.16.0'
  spec.add_dependency 'vsphere-automation-sdk', '~> 6.6'
  spec.add_dependency 'rbvmomi', '~> 1.11'
  spec.add_dependency 'savon', '~> 2.11'

  spec.add_development_dependency 'bundler', '~> 1.7'
  spec.add_development_dependency 'github_changelog_generator'
  spec.add_development_dependency 'rake',    '~> 10.0'
  spec.add_development_dependency 'rubocop', '~> 0.49'
end
