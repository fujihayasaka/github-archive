# -*- encoding: utf-8 -*-
# stub: billing-platform-client 2.41.0 ruby ruby/lib

Gem::Specification.new do |s|
  s.name = "billing-platform-client".freeze
  s.version = "2.41.0".freeze

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.require_paths = ["ruby/lib".freeze]
  s.authors = ["#billing-engineering".freeze]
  s.date = "2026-03-12"
  s.homepage = "https://github.com/github/billing-platform".freeze
  s.rubygems_version = "3.1.2".freeze
  s.summary = "Ruby client for the billing-platform API".freeze

  s.installed_by_version = "4.0.20".freeze

  s.specification_version = 4

  s.add_runtime_dependency(%q<faraday>.freeze, [">= 0.17".freeze, "< 3".freeze])
  s.add_runtime_dependency(%q<twirp>.freeze, ["~> 1.10".freeze])
end
