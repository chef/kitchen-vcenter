source "https://rubygems.org"

gemspec

group :development do
  gem "guard"
  gem "guard-shell"
  gem "chefstyle", git: "https://github.com/chef/chefstyle.git", branch: "master"
end

group :docs do
  gem "github-markup"
  gem "redcarpet"
  gem "yard"
end

group :debug do
  gem "pry"
  gem "pry-byebug"
  gem "pry-stack_explorer"
  gem "rb-readline"
end

instance_eval(ENV["GEMFILE_MOD"]) if ENV["GEMFILE_MOD"]

# If you want to load debugging tools into the bundle exec sandbox,
# add these additional dependencies into Gemfile.local
eval_gemfile(__FILE__ + ".local") if File.exist?(__FILE__ + ".local")
