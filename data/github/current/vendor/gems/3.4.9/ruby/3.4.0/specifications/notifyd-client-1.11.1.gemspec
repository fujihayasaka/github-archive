# -*- encoding: utf-8 -*-
# stub: notifyd-client 1.11.1 ruby lib

Gem::Specification.new do |s|
  s.name = "notifyd-client".freeze
  s.version = "1.11.1".freeze

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.require_paths = ["lib".freeze]
  s.authors = ["@github/notifications".freeze]
  s.date = "2025-09-01"
  s.homepage = "https://github.com/github/notifyd".freeze
  s.rubygems_version = "3.5.22".freeze
  s.summary = "Ruby client for notifyd services".freeze

  s.installed_by_version = "3.6.9".freeze

  s.specification_version = 4

  s.add_runtime_dependency(%q<google-protobuf>.freeze, ["~> 3.14".freeze])
  s.add_runtime_dependency(%q<twirp>.freeze, ["~> 1.10".freeze])
  s.add_runtime_dependency(%q<resilient>.freeze, ["~> 0.4.0".freeze])
  s.add_runtime_dependency(%q<faraday>.freeze, [">= 0.17".freeze, "< 2".freeze])
  s.add_runtime_dependency(%q<sorbet-runtime>.freeze, [">= 0".freeze])
end
