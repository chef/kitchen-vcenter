source "https://rubygems.org"

gemspec

group :development do
  gem "rake"
  gem "rspec"
  gem "cookstyle", ">=7.32.8"
end

group :debug do
  gem "pry"
  gem "pry-byebug"
  gem "pry-stack_explorer"
  gem "rb-readline"
end

# This is a required dependency for windows platforms
platforms :mswin, :mswin64, :mingw, :x64_mingw do
  gem "win32-security"
end
