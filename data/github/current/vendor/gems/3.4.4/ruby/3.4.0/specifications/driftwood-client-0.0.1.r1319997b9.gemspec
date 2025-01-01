# -*- encoding: utf-8 -*-
# stub: driftwood-client 0.0.1.r1319997b9 ruby client/ruby/lib

Gem::Specification.new do |s|
  s.name = "driftwood-client".freeze
  s.version = "0.0.1.r1319997b9".freeze

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.metadata = { "allowed_push_host" => "none", "homepage_uri" => "https://github.com/github/driftwood", "source_code_uri" => "https://github.com/github/driftwood" } if s.respond_to? :metadata=
  s.require_paths = ["client/ruby/lib".freeze]
  s.authors = ["Jeff Saracco".freeze]
  s.bindir = "exe".freeze
  s.date = "2025-01-29"
  s.email = ["jeffsaracco@github.com".freeze]
  s.homepage = "https://github.com/github/driftwood".freeze
  s.rubygems_version = "3.6.2".freeze
  s.summary = "Ruby client for driftwood".freeze

  s.installed_by_version = "3.6.7".freeze

  s.specification_version = 4

  s.add_runtime_dependency(%q<faraday>.freeze, [">= 0.17".freeze, "< 3.0".freeze])
  s.add_runtime_dependency(%q<twirp>.freeze, ["<= 1.14.0".freeze])
  s.add_development_dependency(%q<minitest>.freeze, ["~> 5.0".freeze])
  s.add_development_dependency(%q<minitest-hooks>.freeze, [">= 0".freeze])
  s.add_development_dependency(%q<rubocop-github>.freeze, [">= 0".freeze])
  s.add_development_dependency(%q<mocha>.freeze, ["~> 2.0".freeze])
  s.add_development_dependency(%q<pry>.freeze, ["~> 0.15.0".freeze])
  s.add_development_dependency(%q<activesupport>.freeze, ["~> 8.0.0".freeze])
end
