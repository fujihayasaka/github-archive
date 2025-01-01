# -*- encoding: utf-8 -*-
# stub: authzd-client 0.11.12.r8b9c965f8 ruby ruby/lib

Gem::Specification.new do |s|
  s.name = "authzd-client".freeze
  s.version = "0.11.12.r8b9c965f8".freeze

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.require_paths = ["ruby/lib".freeze]
  s.authors = ["mtodd".freeze, "tarebyte".freeze, "vroldanbet".freeze, "oneill38".freeze, "bryanaknight".freeze]
  s.date = "2025-04-14"
  s.homepage = "https://github.com/github/authzd".freeze
  s.rubygems_version = "3.6.2".freeze
  s.summary = "Ruby client for authzd services".freeze

  s.installed_by_version = "3.6.9".freeze

  s.specification_version = 4

  s.add_runtime_dependency(%q<twirp>.freeze, ["~> 1.10".freeze])
  s.add_runtime_dependency(%q<resilient>.freeze, ["~> 0.4.0".freeze])
  s.add_runtime_dependency(%q<google-protobuf>.freeze, ["~> 3.14".freeze])
  s.add_runtime_dependency(%q<faraday>.freeze, [">= 0".freeze])
  s.add_development_dependency(%q<mocha>.freeze, ["~> 2.1.0".freeze])
  s.add_development_dependency(%q<minitest>.freeze, ["~> 5.25".freeze])
  s.add_development_dependency(%q<minitest-hooks>.freeze, ["~> 1.5".freeze])
  s.add_development_dependency(%q<pry>.freeze, ["~> 0.15".freeze])
  s.add_development_dependency(%q<rack>.freeze, ["~> 3.1.3".freeze])
  s.add_development_dependency(%q<rackup>.freeze, ["~> 2.0".freeze])
  s.add_development_dependency(%q<simplecov>.freeze, ["~> 0.20".freeze])
  s.add_development_dependency(%q<webrick>.freeze, ["~> 1.7".freeze])
  s.add_development_dependency(%q<byebug>.freeze, ["~> 11.1".freeze])
  s.add_development_dependency(%q<debug>.freeze, [">= 0".freeze])
end
