# -*- encoding: utf-8 -*-
# stub: rollup 0.8.0 ruby lib

Gem::Specification.new do |s|
  s.name = "rollup".freeze
  s.version = "0.8.0".freeze

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.require_paths = ["lib".freeze]
  s.authors = ["Misty De Meo".freeze]
  s.bindir = "exe".freeze
  s.date = "1980-01-02"
  s.description = "Generate a unique identifier for an exception".freeze
  s.email = ["mistydemeo@github.com".freeze]
  s.files = [".github/workflows/ruby.yml".freeze, ".gitignore".freeze, ".ruby-version".freeze, ".travis.yml".freeze, "Brewfile".freeze, "Gemfile".freeze, "Gemfile.lock".freeze, "README.md".freeze, "Rakefile".freeze, "lib/rollup.rb".freeze, "lib/rollup/version.rb".freeze, "rollup.gemspec".freeze, "script/bootstrap".freeze, "script/cibuild".freeze, "script/test".freeze]
  s.homepage = "https://github.com/github/rollup".freeze
  s.rubygems_version = "3.6.9".freeze
  s.summary = "Generate a unique identifier for an exception".freeze

  s.installed_by_version = "3.6.9".freeze

  s.specification_version = 4

  s.add_development_dependency(%q<bundler>.freeze, [">= 0".freeze])
  s.add_development_dependency(%q<rake>.freeze, [">= 0".freeze])
  s.add_development_dependency(%q<minitest>.freeze, [">= 0".freeze])
end
