# -*- encoding: utf-8 -*-
# stub: console_auth 1.2.2 ruby lib

Gem::Specification.new do |s|
  s.name = "console_auth".freeze
  s.version = "1.2.2".freeze

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.metadata = { "allowed_push_host" => "https://rubygems.pkg.github.com", "changelog_uri" => "https://github.com/github/console_auth/CHANGELOG.md", "homepage_uri" => "https://github.com/github/console_auth", "source_code_uri" => "https://github.com/github/console_auth" } if s.respond_to? :metadata=
  s.require_paths = ["lib".freeze]
  s.authors = ["GitHub, Inc.".freeze]
  s.bindir = "exe".freeze
  s.date = "1980-01-02"
  s.email = ["security@github.com".freeze]
  s.files = [".github/workflows/main.yml".freeze, ".github/workflows/pr.yml".freeze, ".github/workflows/test.yml".freeze, ".gitignore".freeze, ".rspec".freeze, ".rubocop.yml".freeze, ".ruby-version".freeze, "Gemfile".freeze, "README.md".freeze, "Rakefile".freeze, "bin/console".freeze, "bin/setup".freeze, "bin/vendor-gem".freeze, "console_auth.gemspec".freeze, "lib/console_auth.rb".freeze, "lib/console_auth/version.rb".freeze, "lib/console_monitor.rb".freeze, "vendor/cache/addressable-2.8.0.gem".freeze, "vendor/cache/ast-2.4.2.gem".freeze, "vendor/cache/coderay-1.1.3.gem".freeze, "vendor/cache/crack-0.4.5.gem".freeze, "vendor/cache/diff-lcs-1.4.4.gem".freeze, "vendor/cache/failbot-2.5.5.gem".freeze, "vendor/cache/fido-challenger-client-0.9.gem".freeze, "vendor/cache/hashdiff-1.0.1.gem".freeze, "vendor/cache/method_source-1.0.0.gem".freeze, "vendor/cache/parallel-1.21.0.gem".freeze, "vendor/cache/parser-3.0.2.0.gem".freeze, "vendor/cache/pry-0.14.1.gem".freeze, "vendor/cache/public_suffix-4.0.6.gem".freeze, "vendor/cache/rainbow-3.0.0.gem".freeze, "vendor/cache/rake-13.0.6.gem".freeze, "vendor/cache/regexp_parser-2.1.1.gem".freeze, "vendor/cache/rexml-3.2.5.gem".freeze, "vendor/cache/rspec-3.10.0.gem".freeze, "vendor/cache/rspec-core-3.10.1.gem".freeze, "vendor/cache/rspec-expectations-3.10.1.gem".freeze, "vendor/cache/rspec-mocks-3.10.2.gem".freeze, "vendor/cache/rspec-support-3.10.2.gem".freeze, "vendor/cache/rubocop-1.21.0.gem".freeze, "vendor/cache/rubocop-ast-1.12.0.gem".freeze, "vendor/cache/ruby-progressbar-1.11.0.gem".freeze, "vendor/cache/unicode-display_width-2.1.0.gem".freeze, "vendor/cache/webmock-2.3.2.gem".freeze]
  s.homepage = "https://github.com/github/console_auth".freeze
  s.required_ruby_version = Gem::Requirement.new(">= 2.4.0".freeze)
  s.rubygems_version = "3.6.9".freeze
  s.summary = "Production console access control and logging".freeze

  s.installed_by_version = "3.6.9".freeze

  s.specification_version = 4

  s.add_runtime_dependency(%q<failbot>.freeze, [">= 2.0".freeze, "< 4".freeze])
  s.add_runtime_dependency(%q<fido-challenger-client>.freeze, ["~> 0.5".freeze])
  s.add_development_dependency(%q<pry>.freeze, ["~> 0.14".freeze])
  s.add_development_dependency(%q<rake>.freeze, ["~> 13.0".freeze])
  s.add_development_dependency(%q<rspec>.freeze, ["~> 3.0".freeze])
  s.add_development_dependency(%q<rubocop>.freeze, ["~> 1.7".freeze])
  s.add_development_dependency(%q<webmock>.freeze, ["~> 2.3".freeze])
end
