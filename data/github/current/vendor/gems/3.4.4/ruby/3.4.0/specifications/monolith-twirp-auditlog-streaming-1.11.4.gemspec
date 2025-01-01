# -*- encoding: utf-8 -*-
# stub: monolith-twirp-auditlog-streaming 1.11.4 ruby lib

Gem::Specification.new do |s|
  s.name = "monolith-twirp-auditlog-streaming".freeze
  s.version = "1.11.4".freeze

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.metadata = { "github_repo" => "https://github.com/github/driftwood" } if s.respond_to? :metadata=
  s.require_paths = ["lib".freeze]
  s.authors = ["GitHub".freeze]
  s.date = "2025-02-07"
  s.homepage = "https://github.com/github/driftwood".freeze
  s.licenses = ["Nonstandard".freeze]
  s.required_ruby_version = Gem::Requirement.new(">= 3.0".freeze)
  s.rubygems_version = "3.5.11".freeze
  s.summary = "Generated client/server code for github/github streaming data.".freeze

  s.installed_by_version = "3.6.7".freeze

  s.specification_version = 4

  s.add_runtime_dependency(%q<twirp>.freeze, ["~> 1.10.0".freeze])
  s.add_development_dependency(%q<bundler>.freeze, ["~> 2.5".freeze])
  s.add_development_dependency(%q<minitest>.freeze, ["~> 5.0".freeze])
  s.add_development_dependency(%q<rake>.freeze, ["~> 13.1".freeze])
end
