# -*- encoding: utf-8 -*-
# stub: elm_exporter 0.2.0 ruby lib

Gem::Specification.new do |s|
  s.name = "elm_exporter".freeze
  s.version = "0.2.0".freeze

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.metadata = { "homepage_uri" => "https://github.com/github/elm-exporter", "source_code_uri" => "https://github.com/github/elm-exporter" } if s.respond_to? :metadata=
  s.require_paths = ["lib".freeze]
  s.authors = ["@github/migrations-vnext".freeze]
  s.bindir = "exe".freeze
  s.date = "2026-07-16"
  s.homepage = "https://github.com/github/elm-exporter".freeze
  s.required_ruby_version = Gem::Requirement.new(">= 3.1.0".freeze)
  s.rubygems_version = "3.1.2".freeze
  s.summary = "Ruby TWIRP client for the elm-exporter MigrationManagerAPI".freeze

  s.installed_by_version = "3.6.9".freeze

  s.specification_version = 4

  s.add_runtime_dependency(%q<faraday>.freeze, [">= 0".freeze])
  s.add_runtime_dependency(%q<google-protobuf>.freeze, ["~> 3.14".freeze])
  s.add_runtime_dependency(%q<twirp>.freeze, ["~> 1.10".freeze])
  s.add_development_dependency(%q<irb>.freeze, ["~> 1.14".freeze])
  s.add_development_dependency(%q<minitest>.freeze, ["~> 5.16".freeze])
  s.add_development_dependency(%q<rake>.freeze, ["~> 13.0".freeze])
end
