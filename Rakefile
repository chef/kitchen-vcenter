require "rake"
require "bundler/gem_tasks"

begin
  require "chefstyle"
  require "rubocop/rake_task"
  desc "Run Chefstyle tests"
  RuboCop::RakeTask.new(:style) do |task|
    task.options += ["--display-cop-names", "--no-color"]
  end
rescue LoadError
  puts "chefstyle gem is not installed. bundle install first to make sure all dependencies are installed."
end

RuboCop::RakeTask.new(:style)

begin
  require "rspec/core/rake_task"

  desc "Run all specs in spec directory"
  RSpec::Core::RakeTask.new(:spec) do |t|
    t.verbose = false
    t.rspec_opts = %w{--profile}
    t.pattern = FileList["spec/**/*_spec.rb"]
  end
rescue LoadError
  STDERR.puts "\n*** RSpec not available. (sudo) gem install rspec to run unit tests. ***\n\n"
end

task default: %i{style spec}
