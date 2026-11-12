# -*- encoding: utf-8 -*-
# stub: octo_core 0.12.0 ruby lib

Gem::Specification.new do |s|
  s.name = "octo_core".freeze
  s.version = "0.12.0".freeze

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.metadata = { "allowed_push_host" => "https://rubygems.pkg.github.com/github", "homepage_uri" => "https://github.com/github/gem-trove/gems/octo_core", "source_code_uri" => "https://github.com/github/gem-trove/gems/octo_core" } if s.respond_to? :metadata=
  s.require_paths = ["lib".freeze]
  s.authors = ["Matt Clark".freeze]
  s.bindir = "exe".freeze
  s.date = "2026-05-19"
  s.description = "Common library code leveraged by GitHub's Ruby product server applications such as the monolith itself.".freeze
  s.email = ["44023+mclark@users.noreply.github.com".freeze]
  s.homepage = "https://github.com/github/gem-trove/gems/octo_core".freeze
  s.required_ruby_version = Gem::Requirement.new(">= 3.3.0".freeze)
  s.rubygems_version = "3.5.22".freeze
  s.summary = "The base platform for Ruby GitHub product server applications".freeze

  s.installed_by_version = "4.0.20".freeze

  s.specification_version = 4

  s.add_runtime_dependency(%q<actionpack>.freeze, ["~> 8.0".freeze])
  s.add_runtime_dependency(%q<dogstatsd-ruby>.freeze, ["~> 5.6".freeze])
  s.add_runtime_dependency(%q<rack>.freeze, [">= 2.2".freeze, "< 4".freeze])
  s.add_runtime_dependency(%q<activerecord>.freeze, ["~> 8.0".freeze])
  s.add_runtime_dependency(%q<activesupport>.freeze, ["~> 8.0".freeze])
  s.add_runtime_dependency(%q<faraday>.freeze, [">= 1.0".freeze, "< 3".freeze])
  s.add_runtime_dependency(%q<github-telemetry>.freeze, ["~> 0.50".freeze])
  s.add_runtime_dependency(%q<prelude-batch-loader>.freeze, [">= 0".freeze])
  s.add_runtime_dependency(%q<sorbet-runtime>.freeze, ["~> 0.6.12829".freeze])
  s.add_development_dependency(%q<minitest-stub-const>.freeze, [">= 0".freeze])
  s.add_development_dependency(%q<mocha>.freeze, ["~> 2.7.1".freeze])
  s.add_development_dependency(%q<octo_tools>.freeze, ["~> 0.7".freeze])
  s.add_development_dependency(%q<rubocop>.freeze, ["~> 1.81.7".freeze])
  s.add_development_dependency(%q<rubocop-github>.freeze, ["~> 0.26.0".freeze])
  s.add_development_dependency(%q<rubocop-sorbet>.freeze, ["~> 0.11.0".freeze])
  s.add_development_dependency(%q<sqlite3>.freeze, [">= 0".freeze])
  s.add_development_dependency(%q<tapioca>.freeze, ["~> 0.17.9".freeze])
  s.add_development_dependency(%q<timecop>.freeze, ["~> 0.9.10".freeze])
  s.add_development_dependency(%q<sorbet>.freeze, ["~> 0.6.12829".freeze])
end
