# -*- encoding: utf-8 -*-
# stub: sarif 0.1.3 x86_64-linux lib

Gem::Specification.new do |s|
  s.name = "sarif".freeze
  s.version = "0.1.3".freeze
  s.platform = "x86_64-linux".freeze

  s.required_rubygems_version = Gem::Requirement.new(">= 3.3.11".freeze) if s.respond_to? :required_rubygems_version=
  s.metadata = { "allowed_push_host" => "https://rubygems.pkg.github.com/github", "changelog_uri" => "https://github.com/github/sarif-gem", "github_repo" => "ssh://github.com/github/sarif-gem", "homepage_uri" => "https://github.com/github/sarif-gem", "source_code_uri" => "https://github.com/github/sarif-gem" } if s.respond_to? :metadata=
  s.require_paths = ["lib".freeze]
  s.authors = ["Simon Engledew".freeze]
  s.bindir = "exe".freeze
  s.date = "1980-01-02"
  s.description = "Extracts information from SARIF documents".freeze
  s.email = ["simon-engledew@github.com".freeze]
  s.homepage = "https://github.com/github/sarif-gem".freeze
  s.licenses = ["MIT".freeze]
  s.required_ruby_version = Gem::Requirement.new(">= 2.5".freeze)
  s.rubygems_version = "3.6.7".freeze
  s.summary = "parse, verify and extract SARIF documents".freeze

  s.installed_by_version = "3.6.7".freeze

  s.specification_version = 4

  s.add_development_dependency(%q<minitest>.freeze, ["~> 5.21".freeze])
  s.add_development_dependency(%q<rake>.freeze, ["~> 13.1".freeze])
  s.add_development_dependency(%q<rake-compiler>.freeze, [">= 0".freeze])
  s.add_runtime_dependency(%q<ffi>.freeze, [">= 0".freeze])
  s.add_runtime_dependency(%q<activesupport>.freeze, [">= 0".freeze])
end
