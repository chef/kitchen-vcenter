# frozen_string_literal: true
require 'bundler/gem_tasks'
require 'rspec/core/rake_task'
require 'rubocop/rake_task'

RSpec::Core::RakeTask.new(:spec)
RuboCop::RakeTask.new(:style)

begin
  require 'github_changelog_generator/task'

  GitHubChangelogGenerator::RakeTask.new :changelog do |config|
    config.future_release = KitchenVcenter::VERSION
    config.issues = true
  end
rescue LoadError
  puts 'github_changelog_generator is not available. gem install github_changelog_generator to generate changelogs'
end

task default: [ :spec, :style ]
