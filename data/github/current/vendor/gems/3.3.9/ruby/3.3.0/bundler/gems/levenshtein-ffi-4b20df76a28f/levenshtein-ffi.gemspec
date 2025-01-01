# -*- encoding: utf-8 -*-
# stub: levenshtein-ffi 1.1.0 ruby lib
# stub: ext/levenshtein/extconf.rb

Gem::Specification.new do |s|
  s.name = "levenshtein-ffi".freeze
  s.version = "1.1.0".freeze

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.require_paths = ["lib".freeze]
  s.authors = ["David Balatero".freeze]
  s.date = "2014-08-11"
  s.description = "Provides a fast, cross-Ruby implementation of the levenshtein distance algorithm.".freeze
  s.email = "dbalatero@gmail.com".freeze
  s.extensions = ["ext/levenshtein/extconf.rb".freeze]
  s.extra_rdoc_files = ["README.markdown".freeze]
  s.files = [".rspec".freeze, ".travis.yml".freeze, "CHANGELOG.markdown".freeze, "Gemfile".freeze, "README.markdown".freeze, "Rakefile".freeze, "VERSION".freeze, "ext/levenshtein/.gitignore".freeze, "ext/levenshtein/extconf.rb".freeze, "ext/levenshtein/levenshtein.c".freeze, "ext/levenshtein/levenshtein.h".freeze, "levenshtein-ffi.gemspec".freeze, "lib/levenshtein-ffi.rb".freeze, "lib/levenshtein.rb".freeze, "spec/levenshtein_spec.rb".freeze, "spec/spec_helper.rb".freeze]
  s.homepage = "http://github.com/dbalatero/levenshtein-ffi".freeze
  s.licenses = ["BSD 2-Clause".freeze]
  s.rubygems_version = "2.2.2".freeze
  s.summary = "An FFI version of the levenshtein gem.".freeze

  s.installed_by_version = "3.5.22".freeze

  s.specification_version = 4

  s.add_runtime_dependency(%q<ffi>.freeze, ["~> 1.9".freeze])
  s.add_development_dependency(%q<rspec>.freeze, ["~> 2.99".freeze])
  s.add_development_dependency(%q<jeweler>.freeze, ["~> 2.0".freeze])
end
