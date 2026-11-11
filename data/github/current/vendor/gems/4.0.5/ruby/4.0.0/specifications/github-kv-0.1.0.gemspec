# -*- encoding: utf-8 -*-
# stub: github-kv 0.1.0 ruby lib

Gem::Specification.new do |s|
  s.name = "github-kv".freeze
  s.version = "0.1.0".freeze

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.metadata = { "allowed_push_host" => "https://rubygems.pkg.github.com/github" } if s.respond_to? :metadata=
  s.require_paths = ["lib".freeze]
  s.authors = ["GitHub Open Source".freeze, "Matthew Draper".freeze, "Ahmed Shahin".freeze]
  s.bindir = "exe".freeze
  s.date = "1980-01-02"
  s.description = "A key/value data store backed by MySQL.".freeze
  s.email = ["opensource+github-kv@github.com".freeze, "matthew@trebex.net".freeze, "ahmed.samir.mohamed88@gmail.com".freeze]
  s.homepage = "https://github.com/github/github-kv".freeze
  s.licenses = ["MIT".freeze]
  s.rubygems_version = "4.0.3".freeze
  s.summary = "A key/value data store backed by MySQL.".freeze

  s.installed_by_version = "4.0.10".freeze

  s.specification_version = 4

  s.add_runtime_dependency(%q<activerecord>.freeze, [">= 6.1".freeze])
  s.add_development_dependency(%q<bundler>.freeze, [">= 1.14".freeze])
  s.add_development_dependency(%q<minitest>.freeze, ["~> 5.19".freeze])
  s.add_development_dependency(%q<minitest-focus>.freeze, ["~> 1.1.2".freeze])
  s.add_development_dependency(%q<mocha>.freeze, ["~> 1.2.1".freeze])
  s.add_development_dependency(%q<mysql2>.freeze, [">= 0".freeze])
  s.add_development_dependency(%q<ostruct>.freeze, [">= 0".freeze])
  s.add_development_dependency(%q<pry>.freeze, ["~> 0.12.2".freeze])
  s.add_development_dependency(%q<rake>.freeze, ["~> 12.0".freeze])
  s.add_development_dependency(%q<rubocop-github>.freeze, [">= 0".freeze])
  s.add_development_dependency(%q<timecop>.freeze, [">= 0".freeze])
end
