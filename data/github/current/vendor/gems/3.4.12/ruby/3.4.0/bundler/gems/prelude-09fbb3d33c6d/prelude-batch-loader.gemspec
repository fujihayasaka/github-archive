# -*- encoding: utf-8 -*-
# stub: prelude-batch-loader 0.0.5 ruby lib

Gem::Specification.new do |s|
  s.name = "prelude-batch-loader".freeze
  s.version = "0.0.5".freeze

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.require_paths = ["lib".freeze]
  s.authors = ["John Crepezzi".freeze]
  s.date = "1980-01-02"
  s.email = "john.crepezzi@gmail.com".freeze
  s.files = ["lib/prelude.rb".freeze, "lib/prelude/enumerator.rb".freeze, "lib/prelude/method.rb".freeze, "lib/prelude/preloadable.rb".freeze, "lib/prelude/preloader.rb".freeze, "lib/prelude/version.rb".freeze, "spec/prelude_spec.rb".freeze, "spec/spec_helper.rb".freeze]
  s.licenses = ["MIT".freeze]
  s.rubygems_version = "3.6.7".freeze
  s.summary = "ActiveRecord custom preloading".freeze
  s.test_files = ["spec/prelude_spec.rb".freeze, "spec/spec_helper.rb".freeze]

  s.installed_by_version = "3.6.9".freeze

  s.specification_version = 4

  s.add_runtime_dependency(%q<activerecord>.freeze, [">= 6".freeze])
  s.add_development_dependency(%q<rspec>.freeze, ["~> 3".freeze])
  s.add_development_dependency(%q<sqlite3>.freeze, ["~> 1.4".freeze])
  s.add_development_dependency(%q<rake>.freeze, [">= 0".freeze])
  s.add_development_dependency(%q<pry>.freeze, [">= 0".freeze])
end
