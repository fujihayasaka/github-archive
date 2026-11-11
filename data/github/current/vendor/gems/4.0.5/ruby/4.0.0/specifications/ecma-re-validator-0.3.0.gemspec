# -*- encoding: utf-8 -*-
# stub: ecma-re-validator 0.3.0 ruby lib

Gem::Specification.new do |s|
  s.name = "ecma-re-validator".freeze
  s.version = "0.3.0".freeze

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.require_paths = ["lib".freeze]
  s.authors = ["Garen Torikian".freeze]
  s.date = "2020-12-03"
  s.description = "Validate a regular expression string against what ECMA-262 can actually do.".freeze
  s.email = ["gjtorikian@gmail.com".freeze]
  s.homepage = "https://github.com/gjtorikian/ecma-re-validator".freeze
  s.licenses = ["MIT".freeze]
  s.rubygems_version = "3.1.2".freeze
  s.summary = "Validate a regular expression string against what ECMA-262 can actually do.".freeze

  s.installed_by_version = "4.0.10".freeze

  s.specification_version = 4

  s.add_runtime_dependency(%q<regexp_parser>.freeze, ["~> 2.0".freeze])
  s.add_development_dependency(%q<rspec>.freeze, ["~> 3.1".freeze])
  s.add_development_dependency(%q<rake>.freeze, ["~> 13.0".freeze])
  s.add_development_dependency(%q<awesome_print>.freeze, [">= 0".freeze])
  s.add_development_dependency(%q<pry>.freeze, ["~> 0.10".freeze])
end
