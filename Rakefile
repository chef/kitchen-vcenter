require "bundler/gem_tasks"
require "rubocop/rake_task"
require "yard"

RuboCop::RakeTask.new(:style)
YARD::Rake::YardocTask.new do |t|
  t.files = ["lib/**/*.rb"] # optional
  t.stats_options = ["--list-undoc"] # optional
end

task default: [ :spec, :style ]
