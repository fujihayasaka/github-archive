# -*- encoding: utf-8 -*-
# stub: trino-client 2.2.2 ruby lib

Gem::Specification.new do |s|
  s.name = "trino-client".freeze
  s.version = "2.2.2".freeze

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.require_paths = ["lib".freeze]
  s.authors = ["Sadayuki Furuhashi".freeze]
  s.date = "2025-03-17"
  s.description = "Trino client library".freeze
  s.email = ["sf@treasure-data.com".freeze]
  s.homepage = "https://github.com/treasure-data/trino-client-ruby".freeze
  s.licenses = ["Apache-2.0".freeze]
  s.required_ruby_version = Gem::Requirement.new(">= 3.2.0".freeze)
  s.rubygems_version = "3.1.6".freeze
  s.summary = "Trino client library".freeze

  s.installed_by_version = "3.6.9".freeze

  s.specification_version = 4

  s.add_runtime_dependency(%q<faraday>.freeze, [">= 1".freeze, "< 3".freeze])
  s.add_runtime_dependency(%q<faraday-gzip>.freeze, [">= 1".freeze])
  s.add_runtime_dependency(%q<faraday-follow_redirects>.freeze, [">= 0.3".freeze])
  s.add_runtime_dependency(%q<msgpack>.freeze, [">= 1.5.1".freeze])
  s.add_development_dependency(%q<rake>.freeze, [">= 0.9.2".freeze, "< 14.0".freeze])
  s.add_development_dependency(%q<rspec>.freeze, ["~> 3.13.0".freeze])
  s.add_development_dependency(%q<webmock>.freeze, ["~> 3.0".freeze])
  s.add_development_dependency(%q<addressable>.freeze, ["~> 2.8.1".freeze])
  s.add_development_dependency(%q<simplecov>.freeze, ["~> 0.22.0".freeze])
  s.add_development_dependency(%q<standard>.freeze, ["~> 1.35.0".freeze])
  s.add_development_dependency(%q<psych>.freeze, ["~> 3".freeze])
end
