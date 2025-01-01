# -*- encoding: utf-8 -*-
# stub: view_component 4.0.0.alpha5 ruby lib

Gem::Specification.new do |s|
  s.name = "view_component".freeze
  s.version = "4.0.0.alpha5".freeze

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.metadata = { "allowed_push_host" => "https://rubygems.org", "changelog_uri" => "https://github.com/ViewComponent/view_component/blob/main/docs/CHANGELOG.md", "source_code_uri" => "https://github.com/viewcomponent/view_component" } if s.respond_to? :metadata=
  s.require_paths = ["lib".freeze]
  s.authors = ["ViewComponent Team".freeze]
  s.date = "1980-01-02"
  s.homepage = "https://viewcomponent.org".freeze
  s.licenses = ["MIT".freeze]
  s.required_ruby_version = Gem::Requirement.new(">= 3.2.0".freeze)
  s.rubygems_version = "3.6.8".freeze
  s.summary = "A framework for building reusable, testable & encapsulated view components in Ruby on Rails.".freeze

  s.installed_by_version = "3.6.9".freeze

  s.specification_version = 4

  s.add_runtime_dependency(%q<activesupport>.freeze, [">= 7.1.0".freeze, "< 8.1".freeze])
  s.add_runtime_dependency(%q<concurrent-ruby>.freeze, ["~> 1".freeze])
  s.add_development_dependency(%q<allocation_stats>.freeze, [">= 0".freeze])
  s.add_development_dependency(%q<appraisal>.freeze, ["~> 2".freeze])
  s.add_development_dependency(%q<benchmark-ips>.freeze, ["~> 2".freeze])
  s.add_development_dependency(%q<better_html>.freeze, [">= 0".freeze])
  s.add_development_dependency(%q<bundler>.freeze, ["~> 2".freeze])
  s.add_development_dependency(%q<capybara>.freeze, ["~> 3".freeze])
  s.add_development_dependency(%q<cuprite>.freeze, [">= 0".freeze])
  s.add_development_dependency(%q<erb_lint>.freeze, [">= 0".freeze])
  s.add_development_dependency(%q<haml>.freeze, ["~> 6".freeze])
  s.add_development_dependency(%q<jbuilder>.freeze, ["~> 2".freeze])
  s.add_development_dependency(%q<m>.freeze, ["~> 1".freeze])
  s.add_development_dependency(%q<method_source>.freeze, ["~> 1".freeze])
  s.add_development_dependency(%q<minitest>.freeze, ["~> 5".freeze])
  s.add_development_dependency(%q<puma>.freeze, ["~> 6".freeze])
  s.add_development_dependency(%q<rake>.freeze, ["~> 13".freeze])
  s.add_development_dependency(%q<redis>.freeze, [">= 0".freeze])
  s.add_development_dependency(%q<rspec-rails>.freeze, ["~> 7".freeze])
  s.add_development_dependency(%q<rubocop-md>.freeze, ["~> 2".freeze])
  s.add_development_dependency(%q<selenium-webdriver>.freeze, ["~> 4".freeze])
  s.add_development_dependency(%q<simplecov-console>.freeze, ["< 1".freeze])
  s.add_development_dependency(%q<simplecov>.freeze, ["< 1".freeze])
  s.add_development_dependency(%q<slim>.freeze, ["~> 5".freeze])
  s.add_development_dependency(%q<sprockets-rails>.freeze, ["~> 3".freeze])
  s.add_development_dependency(%q<standard>.freeze, ["~> 1".freeze])
  s.add_development_dependency(%q<turbo-rails>.freeze, ["~> 2".freeze])
  s.add_development_dependency(%q<warning>.freeze, [">= 0".freeze])
  s.add_development_dependency(%q<yard-activesupport-concern>.freeze, ["< 1".freeze])
  s.add_development_dependency(%q<yard>.freeze, ["< 1".freeze])
  s.add_development_dependency(%q<propshaft>.freeze, ["~> 1".freeze])
end
