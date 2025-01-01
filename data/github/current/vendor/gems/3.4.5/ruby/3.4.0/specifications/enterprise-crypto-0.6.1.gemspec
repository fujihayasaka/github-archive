# -*- encoding: utf-8 -*-
# stub: enterprise-crypto 0.6.1 ruby lib

Gem::Specification.new do |s|
  s.name = "enterprise-crypto".freeze
  s.version = "0.6.1".freeze

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.require_paths = ["lib".freeze]
  s.authors = ["Sean Bryant".freeze, "Ben Burkert".freeze]
  s.date = "2025-02-12"
  s.description = "A library for working with customer licenses, VM release keys, and GitHub code release keys.".freeze
  s.email = "sbryant@github.com".freeze
  s.executables = ["enterprise-readkey".freeze]
  s.files = ["bin/enterprise-readkey".freeze]
  s.homepage = "http://github.com/github/enterprise-crypto".freeze
  s.required_ruby_version = Gem::Requirement.new(">= 2.0".freeze)
  s.rubygems_version = "3.4.20".freeze
  s.summary = "A library for working with customer licenses, VM release keys, and GitHub code release keys.".freeze

  s.installed_by_version = "3.6.9".freeze

  s.specification_version = 4

  s.add_runtime_dependency(%q<gpgme>.freeze, ["~> 2.0.24".freeze])
end
