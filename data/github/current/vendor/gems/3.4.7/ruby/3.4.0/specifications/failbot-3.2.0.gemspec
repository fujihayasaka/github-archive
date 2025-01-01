# -*- encoding: utf-8 -*-
# stub: failbot 3.2.0 ruby lib

Gem::Specification.new do |s|
  s.name = "failbot".freeze
  s.version = "3.2.0".freeze

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.metadata = { "allowed_push_host" => "https://rubygems.pkg.github.com/github" } if s.respond_to? :metadata=
  s.require_paths = ["lib".freeze]
  s.authors = ["GitHub Observability Team".freeze]
  s.date = "2025-02-19"
  s.description = "...".freeze
  s.email = ["observability@github.com".freeze]
  s.homepage = "http://github.com/github/failbot#readme".freeze
  s.licenses = ["MIT".freeze]
  s.required_ruby_version = Gem::Requirement.new(">= 3.1".freeze)
  s.rubygems_version = "3.6.2".freeze
  s.summary = "Deliver exceptions to Haystack".freeze

  s.installed_by_version = "3.6.9".freeze

  s.specification_version = 4

  s.add_runtime_dependency(%q<resilient>.freeze, [">= 0.4".freeze])
  s.add_development_dependency(%q<base64>.freeze, ["~> 0.2".freeze])
  s.add_development_dependency(%q<bigdecimal>.freeze, ["~> 3.1".freeze])
  s.add_development_dependency(%q<rails>.freeze, [">= 6.1".freeze, "< 8.0".freeze])
  s.add_development_dependency(%q<rake>.freeze, [">= 10.0".freeze])
  s.add_development_dependency(%q<rack>.freeze, [">= 2.0".freeze, "< 3".freeze])
  s.add_development_dependency(%q<rack-test>.freeze, ["~> 0.6".freeze])
  s.add_development_dependency(%q<m>.freeze, ["~> 1.6".freeze])
  s.add_development_dependency(%q<minitest>.freeze, [">= 5.0".freeze])
  s.add_development_dependency(%q<minitest-stub-const>.freeze, [">= 0.6".freeze])
  s.add_development_dependency(%q<mocha>.freeze, [">= 2.5.0".freeze])
  s.add_development_dependency(%q<mutex_m>.freeze, ["~> 0.2".freeze])
  s.add_development_dependency(%q<webmock>.freeze, [">= 3.0".freeze])
  s.add_development_dependency(%q<pry>.freeze, ["~> 0.14".freeze])
  s.add_development_dependency(%q<solargraph>.freeze, ["~> 0.50".freeze])
  s.add_development_dependency(%q<ruby-lsp>.freeze, ["~> 0.13".freeze])
  s.add_development_dependency(%q<rubocop-github>.freeze, ["~> 0.20".freeze])
  s.add_development_dependency(%q<appraisal>.freeze, [">= 0".freeze])
end
