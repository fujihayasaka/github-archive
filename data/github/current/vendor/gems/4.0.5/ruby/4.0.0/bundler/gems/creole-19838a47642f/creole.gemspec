# -*- encoding: utf-8 -*-
# stub: creole 0.5.0 ruby lib

Gem::Specification.new do |s|
  s.name = "creole".freeze
  s.version = "0.5.0".freeze

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.require_paths = ["lib".freeze]
  s.authors = ["Lars Christensen".freeze, "Daniel Mendler".freeze]
  s.date = "2026-05-27"
  s.description = "Creole is a lightweight markup language (http://wikicreole.org/).".freeze
  s.email = ["larsch@belunktum.dk".freeze, "mail@daniel-mendler.de".freeze]
  s.extra_rdoc_files = ["README.creole".freeze]
  s.files = [".gitignore".freeze, ".travis.yml".freeze, "CHANGES".freeze, "Gemfile".freeze, "LICENSE".freeze, "README.creole".freeze, "Rakefile".freeze, "creole.gemspec".freeze, "lib/creole.rb".freeze, "lib/creole/parser.rb".freeze, "lib/creole/version.rb".freeze, "test/parser_test.rb".freeze]
  s.homepage = "http://github.com/minad/creole".freeze
  s.licenses = ["Ruby".freeze]
  s.rubygems_version = "4.0.6".freeze
  s.summary = "Lightweight markup language".freeze

  s.installed_by_version = "4.0.10".freeze

  s.specification_version = 4

  s.add_development_dependency(%q<bacon>.freeze, [">= 0".freeze])
  s.add_development_dependency(%q<rake>.freeze, [">= 0".freeze])
end
