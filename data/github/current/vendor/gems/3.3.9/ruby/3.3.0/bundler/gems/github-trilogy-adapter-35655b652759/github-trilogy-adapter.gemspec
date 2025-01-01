# -*- encoding: utf-8 -*-
# stub: github-trilogy-adapter 3.0.0 ruby lib

Gem::Specification.new do |s|
  s.name = "github-trilogy-adapter".freeze
  s.version = "3.0.0".freeze

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.metadata = { "bug_tracker_uri" => "https://github.com/github/github-trilogy-adapter/issues", "changelog_uri" => "https://github.com/github/github-trilogy-adapter/blob/master/CHANGELOG.md", "source_code_uri" => "https://github.com/github/github-trilogy-adapter" } if s.respond_to? :metadata=
  s.require_paths = ["lib".freeze]
  s.authors = ["GitHub Engineering".freeze]
  s.date = "2025-11-12"
  s.email = ["opensource+trilogy@github.com".freeze]
  s.extra_rdoc_files = ["README.md".freeze, "LICENSE.md".freeze]
  s.files = ["LICENSE.md".freeze, "README.md".freeze, "lib/github-trilogy-adapter.rb".freeze, "lib/github_trilogy_adapter".freeze, "lib/github_trilogy_adapter/connection_instrumentation.rb".freeze, "lib/github_trilogy_adapter/deadlock_retries.rb".freeze, "lib/github_trilogy_adapter/driver.rb".freeze, "lib/github_trilogy_adapter/native_database_types.rb".freeze, "lib/github_trilogy_adapter/query_data.rb".freeze, "lib/github_trilogy_adapter/query_retries.rb".freeze, "lib/github_trilogy_adapter/quoting.rb".freeze, "lib/github_trilogy_adapter/schema_version.rb".freeze, "lib/github_trilogy_adapter/support_overrides.rb".freeze, "lib/github_trilogy_adapter/version.rb".freeze]
  s.homepage = "https://github.com/github/github-trilogy-adapter".freeze
  s.licenses = ["MIT".freeze]
  s.required_ruby_version = Gem::Requirement.new("~> 3.0".freeze)
  s.rubygems_version = "3.5.22".freeze
  s.summary = "github/github customizations for https://github.com/github/trilogy-adapter.".freeze

  s.installed_by_version = "3.5.22".freeze

  s.specification_version = 4

  s.add_runtime_dependency(%q<trilogy>.freeze, [">= 2.3.0".freeze])
  s.add_runtime_dependency(%q<activerecord>.freeze, [">= 7.1.0.alpha.a".freeze])
  s.add_development_dependency(%q<minitest>.freeze, ["~> 5.11".freeze])
  s.add_development_dependency(%q<minitest-focus>.freeze, ["~> 1.1".freeze])
  s.add_development_dependency(%q<pry>.freeze, ["~> 0.10".freeze])
  s.add_development_dependency(%q<rake>.freeze, ["~> 12.3".freeze])
  s.add_development_dependency(%q<debug>.freeze, [">= 1.0.0".freeze])
end
