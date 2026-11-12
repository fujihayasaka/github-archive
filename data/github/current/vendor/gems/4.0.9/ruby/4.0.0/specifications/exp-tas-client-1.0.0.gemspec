# -*- encoding: utf-8 -*-
# stub: exp-tas-client 1.0.0 ruby lib

Gem::Specification.new do |s|
  s.name = "exp-tas-client".freeze
  s.version = "1.0.0".freeze

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.metadata = { "github_repo" => "ssh://github.com/github/exp-tas" } if s.respond_to? :metadata=
  s.require_paths = ["lib".freeze]
  s.authors = ["github/feature-management".freeze]
  s.date = "2026-03-26"
  s.description = "REST API for experiment treatment assignment via the EXP Go SDK.".freeze
  s.homepage = "https://github.com/github/exp-tas".freeze
  s.licenses = ["Nonstandard".freeze]
  s.required_ruby_version = Gem::Requirement.new(">= 2.7".freeze)
  s.rubygems_version = "3.6.2".freeze
  s.summary = "EXP Treatment Assignment Service Ruby Gem".freeze

  s.installed_by_version = "4.0.20".freeze

  s.specification_version = 4

  s.add_runtime_dependency(%q<faraday>.freeze, [">= 1.0.1".freeze, "< 3.0".freeze])
  s.add_runtime_dependency(%q<faraday-multipart>.freeze, [">= 0".freeze])
  s.add_runtime_dependency(%q<marcel>.freeze, [">= 0".freeze])
  s.add_development_dependency(%q<rspec>.freeze, ["~> 3.6".freeze, ">= 3.6.0".freeze])
end
