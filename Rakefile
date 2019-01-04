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

require "yard"

RuboCop::RakeTask.new(:style)
YARD::Rake::YardocTask.new do |t|
  t.files = ["lib/**/*.rb"] # optional
  t.stats_options = ["--list-undoc"] # optional
end

task default: [:style]
