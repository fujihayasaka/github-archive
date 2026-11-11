# -*- encoding: utf-8 -*-
# stub: octo_db 1.1.0 ruby lib

Gem::Specification.new do |s|
  s.name = "octo_db".freeze
  s.version = "1.1.0".freeze

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.metadata = { "allowed_push_host" => "https://rubygems.pkg.github.com/github", "homepage_uri" => "https://github.com/github/gem-trove/octo_tools/gems/octo_db", "source_code_uri" => "https://github.com/github/gem-trove/octo_tools/gems/octo_db" } if s.respond_to? :metadata=
  s.require_paths = ["lib".freeze]
  s.authors = ["Matt Clark".freeze]
  s.bindir = "exe".freeze
  s.date = "2025-12-11"
  s.description = "Inner sourcing of GitHub's MySQL platform code.".freeze
  s.email = ["44023+mclark@users.noreply.github.com".freeze]
  s.homepage = "https://github.com/github/gem-trove/octo_tools/gems/octo_db".freeze
  s.required_ruby_version = Gem::Requirement.new(">= 3.3.0".freeze)
  s.rubygems_version = "3.5.22".freeze
  s.summary = "Inner sourcing of GitHub's MySQL platform code.".freeze

  s.installed_by_version = "4.0.3".freeze

  s.specification_version = 4

  s.add_runtime_dependency(%q<sorbet-runtime>.freeze, ["~> 0.6.12829".freeze])
  s.add_runtime_dependency(%q<activesupport>.freeze, ["~> 8.1".freeze])
  s.add_runtime_dependency(%q<activerecord>.freeze, ["~> 8.1".freeze])
  s.add_development_dependency(%q<mocha>.freeze, ["~> 2.7.1".freeze])
  s.add_development_dependency(%q<octo_tools>.freeze, ["~> 0.7.0".freeze])
  s.add_development_dependency(%q<rubocop>.freeze, ["~> 1.81.7".freeze])
  s.add_development_dependency(%q<rubocop-github>.freeze, ["~> 0.26.0".freeze])
  s.add_development_dependency(%q<rubocop-sorbet>.freeze, ["~> 0.11.0".freeze])
  s.add_development_dependency(%q<sorbet>.freeze, ["~> 0.6.12829".freeze])
  s.add_development_dependency(%q<sqlite3>.freeze, [">= 0".freeze])
  s.add_development_dependency(%q<tapioca>.freeze, ["~> 0.17.9".freeze])
end
