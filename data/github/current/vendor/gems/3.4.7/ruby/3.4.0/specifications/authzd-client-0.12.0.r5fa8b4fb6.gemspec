# -*- encoding: utf-8 -*-
# stub: authzd-client 0.12.0.r5fa8b4fb6 ruby ruby/lib

Gem::Specification.new do |s|
  s.name = "authzd-client".freeze
  s.version = "0.12.0.r5fa8b4fb6".freeze

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.require_paths = ["ruby/lib".freeze]
  s.authors = ["mtodd".freeze, "tarebyte".freeze, "vroldanbet".freeze, "oneill38".freeze, "bryanaknight".freeze]
  s.date = "1980-01-02"
  s.homepage = "https://github.com/github/authzd".freeze
  s.rubygems_version = "3.6.9".freeze
  s.summary = "Ruby client for authzd services".freeze

  s.installed_by_version = "3.6.9".freeze

  s.specification_version = 4

  s.add_runtime_dependency(%q<twirp>.freeze, ["~> 1.10".freeze])
  s.add_runtime_dependency(%q<resilient>.freeze, ["~> 0.4.0".freeze])
  s.add_runtime_dependency(%q<google-protobuf>.freeze, ["~> 3.14".freeze])
  s.add_runtime_dependency(%q<faraday>.freeze, [">= 0".freeze])
  s.add_development_dependency(%q<mocha>.freeze, ["~> 2.1.0".freeze])
  s.add_development_dependency(%q<minitest>.freeze, ["~> 5.25".freeze])
  s.add_development_dependency(%q<minitest-hooks>.freeze, ["~> 1.5".freeze])
  s.add_development_dependency(%q<pry>.freeze, ["~> 0.15".freeze])
  s.add_development_dependency(%q<rack>.freeze, ["~> 3.1.3".freeze])
  s.add_development_dependency(%q<rackup>.freeze, ["~> 2.0".freeze])
  s.add_development_dependency(%q<simplecov>.freeze, ["~> 0.20".freeze])
  s.add_development_dependency(%q<webrick>.freeze, ["~> 1.7".freeze])
  s.add_development_dependency(%q<byebug>.freeze, ["~> 12.0".freeze])
  s.add_development_dependency(%q<debug>.freeze, [">= 0".freeze])
  s.add_development_dependency(%q<rubocop-github>.freeze, ["~> 0.26.0".freeze])
  s.add_development_dependency(%q<rubocop-performance>.freeze, ["~> 1.25".freeze])
  s.add_development_dependency(%q<ruby-lsp>.freeze, ["~> 0.26.0".freeze])
end
