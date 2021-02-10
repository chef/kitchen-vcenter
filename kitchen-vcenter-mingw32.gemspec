gemspec = eval(IO.read(File.expand_path("kitchen-vcenter.gemspec", __dir__)))

gemspec.platform = Gem::Platform.new(%w{universal mingw32})

gemspec.add_dependency "win32-security", "~> 0.5.0"

gemspec
