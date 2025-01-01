# -*- encoding: utf-8 -*-
# stub: pitchfork 0.17.0 ruby lib
# stub: ext/pitchfork_http/extconf.rb

Gem::Specification.new do |s|
  s.name = "pitchfork".freeze
  s.version = "0.17.0".freeze

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.require_paths = ["lib".freeze]
  s.authors = ["Jean Boussier".freeze]
  s.bindir = "exe".freeze
  s.date = "2025-03-24"
  s.description = "`pitchfork` is a preforking HTTP server for Rack applications designed\nto minimize memory usage by maximizing Copy-on-Write performance.".freeze
  s.email = ["jean.boussier@gmail.com".freeze]
  s.executables = ["pitchfork".freeze]
  s.extensions = ["ext/pitchfork_http/extconf.rb".freeze]
  s.files = ["exe/pitchfork".freeze, "ext/pitchfork_http/extconf.rb".freeze]
  s.homepage = "https://github.com/Shopify/pitchfork".freeze
  s.licenses = ["GPL-2.0+".freeze, "Ruby".freeze]
  s.required_ruby_version = Gem::Requirement.new(">= 2.5.0".freeze)
  s.rubygems_version = "3.5.9".freeze
  s.summary = "Rack HTTP server for fast clients and Unix".freeze

  s.installed_by_version = "3.6.9".freeze

  s.specification_version = 4

  s.add_runtime_dependency(%q<rack>.freeze, [">= 2.0".freeze])
  s.add_runtime_dependency(%q<logger>.freeze, [">= 0".freeze])
end
