# -*- encoding: utf-8 -*-
# stub: aqueduct-client 1.3.3 ruby lib

Gem::Specification.new do |s|
  s.name = "aqueduct-client".freeze
  s.version = "1.3.3".freeze

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.metadata = { "allowed_push_host" => "https://rubygems.pkg.github.com/github", "changelog_uri" => "https://github.com/github/aqueduct-client-ruby", "github_repo" => "ssh://github.com/github/aqueduct-client-ruby", "homepage_uri" => "https://github.com/github/aqueduct-client-ruby", "source_code_uri" => "https://github.com/github/aqueduct-client-ruby" } if s.respond_to? :metadata=
  s.require_paths = ["lib".freeze]
  s.authors = ["@github/data-pipelines".freeze]
  s.bindir = "exe".freeze
  s.date = "2025-02-07"
  s.homepage = "https://github.com/github/aqueduct-client-ruby".freeze
  s.licenses = ["MIT".freeze]
  s.rubygems_version = "3.6.2".freeze
  s.summary = "An aqueduct client for ruby".freeze

  s.installed_by_version = "3.6.7".freeze

  s.specification_version = 4

  s.add_runtime_dependency(%q<google-protobuf>.freeze, [">= 3.12".freeze, "< 5.0".freeze])
  s.add_runtime_dependency(%q<twirp>.freeze, [">= 1.1".freeze])
  s.add_runtime_dependency(%q<faraday>.freeze, [">= 0".freeze])
  s.add_runtime_dependency(%q<nanoid>.freeze, [">= 0".freeze])
  s.add_development_dependency(%q<bundler>.freeze, ["~> 2".freeze])
  s.add_development_dependency(%q<rake>.freeze, ["~> 13.0".freeze])
  s.add_development_dependency(%q<rspec>.freeze, ["~> 3.0".freeze])
  s.add_development_dependency(%q<rack>.freeze, [">= 0".freeze])
  s.add_development_dependency(%q<rackup>.freeze, [">= 0".freeze])
  s.add_development_dependency(%q<webrick>.freeze, [">= 0".freeze])
end
