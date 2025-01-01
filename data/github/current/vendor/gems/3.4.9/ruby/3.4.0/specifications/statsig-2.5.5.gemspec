# -*- encoding: utf-8 -*-
# stub: statsig 2.5.5 ruby lib

Gem::Specification.new do |s|
  s.name = "statsig".freeze
  s.version = "2.5.5".freeze

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.require_paths = ["lib".freeze]
  s.authors = ["Statsig, Inc".freeze]
  s.date = "2025-08-11"
  s.description = "Statsig server SDK for feature gates and experimentation in Ruby".freeze
  s.email = "support@statsig.com".freeze
  s.homepage = "https://rubygems.org/gems/statsig".freeze
  s.licenses = ["ISC".freeze]
  s.required_ruby_version = Gem::Requirement.new(">= 2.5.0".freeze)
  s.rubygems_version = "3.2.33".freeze
  s.summary = "Statsig server SDK for Ruby".freeze

  s.installed_by_version = "3.6.9".freeze

  s.specification_version = 4

  s.add_development_dependency(%q<bundler>.freeze, ["~> 2.0".freeze])
  s.add_development_dependency(%q<webmock>.freeze, ["~> 3.13".freeze])
  s.add_development_dependency(%q<minitest>.freeze, ["~> 5.14.0".freeze])
  s.add_development_dependency(%q<minitest-reporters>.freeze, ["~> 1.6".freeze])
  s.add_development_dependency(%q<minitest-suite>.freeze, ["~> 0.0.3".freeze])
  s.add_development_dependency(%q<spy>.freeze, ["~> 1.0".freeze])
  s.add_development_dependency(%q<mutex_m>.freeze, ["~> 0.2.0".freeze])
  s.add_development_dependency(%q<tapioca>.freeze, ["~> 0.4.27".freeze])
  s.add_development_dependency(%q<sinatra>.freeze, ["~> 2.2".freeze])
  s.add_development_dependency(%q<puma>.freeze, ["~> 6.0".freeze])
  s.add_development_dependency(%q<rubocop>.freeze, ["~> 1.28.2".freeze])
  s.add_development_dependency(%q<parallel_tests>.freeze, ["~> 2.7".freeze])
  s.add_development_dependency(%q<simplecov>.freeze, ["~> 0.21".freeze])
  s.add_development_dependency(%q<simplecov-lcov>.freeze, ["~> 0.7.0".freeze])
  s.add_development_dependency(%q<simplecov-cobertura>.freeze, ["~> 2.1".freeze])
  s.add_runtime_dependency(%q<user_agent_parser>.freeze, ["~> 2.18.0".freeze])
  s.add_runtime_dependency(%q<http>.freeze, [">= 4.4".freeze, "< 6.0".freeze])
  s.add_runtime_dependency(%q<connection_pool>.freeze, ["~> 2.4".freeze, ">= 2.4.1".freeze])
  s.add_runtime_dependency(%q<ip3country>.freeze, ["~> 0.2.1".freeze])
  s.add_runtime_dependency(%q<concurrent-ruby>.freeze, ["~> 1.1".freeze])
  s.add_runtime_dependency(%q<zlib>.freeze, ["~> 3.1.0".freeze])
end
