# -*- encoding: utf-8 -*-
# stub: unicorn 6.1.0.1.gbd68 ruby lib
# stub: ext/unicorn_http/extconf.rb

Gem::Specification.new do |s|
  s.name = "unicorn".freeze
  s.version = "6.1.0.1.gbd68".freeze

  s.required_rubygems_version = Gem::Requirement.new("> 1.3.1".freeze) if s.respond_to? :required_rubygems_version=
  s.require_paths = ["lib".freeze]
  s.authors = ["unicorn hackers".freeze]
  s.date = "2024-10-29"
  s.description = "unicorn is an HTTP server for Rack applications designed to only serve\nfast clients on low-latency, high-bandwidth connections and take\nadvantage of features in Unix/Unix-like kernels.  Slow clients should\nonly be served by placing a reverse proxy capable of fully buffering\nboth the the request and response in between unicorn and slow clients.".freeze
  s.email = "unicorn-public@yhbt.net".freeze
  s.executables = ["unicorn".freeze, "unicorn_rails".freeze]
  s.extensions = ["ext/unicorn_http/extconf.rb".freeze]
  s.extra_rdoc_files = ["FAQ".freeze, "README".freeze, "TUNING".freeze, "PHILOSOPHY".freeze, "HACKING".freeze, "DESIGN".freeze, "CONTRIBUTORS".freeze, "LICENSE".freeze, "SIGNALS".freeze, "KNOWN_ISSUES".freeze, "TODO".freeze, "NEWS".freeze, "LATEST".freeze, "lib/unicorn.rb".freeze, "lib/unicorn/configurator.rb".freeze, "lib/unicorn/http_server.rb".freeze, "lib/unicorn/preread_input.rb".freeze, "lib/unicorn/stream_input.rb".freeze, "lib/unicorn/tee_input.rb".freeze, "lib/unicorn/util.rb".freeze, "lib/unicorn/oob_gc.rb".freeze, "lib/unicorn/worker.rb".freeze, "ISSUES".freeze, "Sandbox".freeze, "Links".freeze, "Application_Timeouts".freeze]
  s.files = ["Application_Timeouts".freeze, "CONTRIBUTORS".freeze, "DESIGN".freeze, "FAQ".freeze, "HACKING".freeze, "ISSUES".freeze, "KNOWN_ISSUES".freeze, "LATEST".freeze, "LICENSE".freeze, "Links".freeze, "NEWS".freeze, "PHILOSOPHY".freeze, "README".freeze, "SIGNALS".freeze, "Sandbox".freeze, "TODO".freeze, "TUNING".freeze, "bin/unicorn".freeze, "bin/unicorn_rails".freeze, "ext/unicorn_http/extconf.rb".freeze, "lib/unicorn.rb".freeze, "lib/unicorn/configurator.rb".freeze, "lib/unicorn/http_server.rb".freeze, "lib/unicorn/oob_gc.rb".freeze, "lib/unicorn/preread_input.rb".freeze, "lib/unicorn/stream_input.rb".freeze, "lib/unicorn/tee_input.rb".freeze, "lib/unicorn/util.rb".freeze, "lib/unicorn/worker.rb".freeze]
  s.homepage = "https://yhbt.net/unicorn/".freeze
  s.licenses = ["GPL-2.0+".freeze, "Ruby-1.8".freeze]
  s.required_ruby_version = Gem::Requirement.new(">= 2.0.0".freeze)
  s.rubygems_version = "3.1.2".freeze
  s.summary = "Rack HTTP server for fast clients and Unix".freeze

  s.installed_by_version = "3.5.22".freeze

  s.specification_version = 4

  s.add_development_dependency(%q<rack>.freeze, [">= 0".freeze])
  s.add_runtime_dependency(%q<kgio>.freeze, ["~> 2.6".freeze])
  s.add_runtime_dependency(%q<raindrops>.freeze, ["~> 0.7".freeze])
  s.add_development_dependency(%q<test-unit>.freeze, ["~> 3.0".freeze])
end
