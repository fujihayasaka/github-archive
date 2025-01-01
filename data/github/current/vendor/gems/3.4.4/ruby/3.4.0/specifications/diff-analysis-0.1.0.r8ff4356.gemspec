# -*- encoding: utf-8 -*-
# stub: diff-analysis 0.1.0.r8ff4356 ruby lib

Gem::Specification.new do |s|
  s.name = "diff-analysis".freeze
  s.version = "0.1.0.r8ff4356".freeze

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.require_paths = ["lib".freeze]
  s.authors = ["Colin Merkel <colinwm@github.com>".freeze]
  s.date = "2024-09-11"
  s.homepage = "https://github.com/github/diff-analysis".freeze
  s.rubygems_version = "3.5.16".freeze
  s.summary = "Ruby client for the diff analysis service".freeze

  s.installed_by_version = "3.6.7".freeze

  s.specification_version = 4

  s.add_runtime_dependency(%q<twirp>.freeze, ["~> 1.10".freeze])
  s.add_development_dependency(%q<bundler>.freeze, [">= 0".freeze])
  s.add_development_dependency(%q<rake>.freeze, [">= 0".freeze])
  s.add_development_dependency(%q<rspec>.freeze, [">= 0".freeze])
  s.add_development_dependency(%q<rack>.freeze, [">= 0".freeze])
end
