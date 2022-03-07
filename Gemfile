source "https://rubygems.org"

gemspec

group :development do
  gem "rake"
  gem "rspec"
  gem "chefstyle", "2.2.2"
end

group :debug do
  gem "pry"
  gem "pry-byebug"
  gem "pry-stack_explorer"
  gem "rb-readline"
end

# This is a required dependency for windows platforms
platforms :mswin, :mingw, :x64_mingw do
  gem "win32-security"
end
