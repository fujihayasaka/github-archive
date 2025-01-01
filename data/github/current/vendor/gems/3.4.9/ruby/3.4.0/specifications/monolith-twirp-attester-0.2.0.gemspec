# -*- encoding: utf-8 -*-
# stub: monolith-twirp-attester 0.2.0 ruby lib

Gem::Specification.new do |s|
  s.name = "monolith-twirp-attester".freeze
  s.version = "0.2.0".freeze

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.require_paths = ["lib".freeze]
  s.authors = ["Package Security".freeze]
  s.date = "2025-07-31"
  s.description = "Attester Ruby client".freeze
  s.email = ["package-security@github.com".freeze]
  s.homepage = "https://github.com/github/attester".freeze
  s.required_ruby_version = Gem::Requirement.new(">= 3.3".freeze)
  s.rubygems_version = "3.5.22".freeze
  s.summary = "Attester Ruby client".freeze

  s.installed_by_version = "3.6.9".freeze

  s.specification_version = 4

  s.add_runtime_dependency(%q<twirp>.freeze, ["~> 1.1".freeze])
  s.add_runtime_dependency(%q<faraday>.freeze, [">= 0.17".freeze])
  s.add_runtime_dependency(%q<sorbet-runtime>.freeze, [">= 0".freeze])
  s.add_runtime_dependency(%q<sigstore-proto>.freeze, [">= 0".freeze])
  s.add_development_dependency(%q<bundler>.freeze, ["~> 2.5".freeze])
  s.add_development_dependency(%q<minitest>.freeze, ["~> 5.25".freeze])
  s.add_development_dependency(%q<pry>.freeze, [">= 0".freeze])
  s.add_development_dependency(%q<rake>.freeze, [">= 0".freeze])
  s.add_development_dependency(%q<vcr>.freeze, ["~> 6.3".freeze])
  s.add_development_dependency(%q<webmock>.freeze, ["~> 3.23".freeze])
  s.add_development_dependency(%q<sorbet>.freeze, [">= 0".freeze])
  s.add_development_dependency(%q<minitest-snapshots>.freeze, ["~> 1.1".freeze])
end
