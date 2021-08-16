source "https://rubygems.org"

gemspec

group :development do
  gem "rake"
  gem "chefstyle", "2.0.8"
  if Gem::Version.new(RUBY_VERSION) < Gem::Version.new("2.6") # Remove this entirely once Ruby 2.5 support ends
    gem "chef-utils", "< 16.7"
  end
end

group :debug do
  gem "pry"
  gem "pry-byebug"
  if Gem::Version.new(RUBY_VERSION) < Gem::Version.new("2.6") # Remove this pin once Ruby 2.5 support ends
    gem "pry-stack_explorer", "< 0.5"
  end
  gem "rb-readline"
end
