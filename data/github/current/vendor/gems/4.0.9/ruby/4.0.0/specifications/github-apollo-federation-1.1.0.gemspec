# -*- encoding: utf-8 -*-
# stub: github-apollo-federation 1.1.0 ruby lib

Gem::Specification.new do |s|
  s.name = "github-apollo-federation".freeze
  s.version = "1.1.0".freeze

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.metadata = { "bug_tracker_uri" => "https://github.com/github/apollo-federation-ruby/issues", "changelog_uri" => "https://github.com/github/apollo-federation-ruby/releases", "github_repo" => "https://github.com/github/apollo-federation-ruby", "homepage_uri" => "https://github.com/github/apollo-federation-ruby" } if s.respond_to? :metadata=
  s.require_paths = ["lib".freeze]
  s.authors = ["@github/graphql-platform".freeze]
  s.date = "2025-11-04"
  s.description = "The GitHub GraphQL Platform Team's hard fork of the `Gusto/apollo-federation-ruby` repository".freeze
  s.homepage = "https://github.com/github/apollo-federation-ruby".freeze
  s.licenses = ["MIT".freeze]
  s.required_ruby_version = Gem::Requirement.new(">= 2.2.0".freeze)
  s.rubygems_version = "3.4.20".freeze
  s.summary = "A Ruby implementation of Apollo Federation".freeze

  s.installed_by_version = "4.0.20".freeze

  s.specification_version = 4

  s.add_runtime_dependency(%q<graphql>.freeze, [">= 0".freeze])
  s.add_development_dependency(%q<actionpack>.freeze, [">= 0".freeze])
  s.add_development_dependency(%q<debug>.freeze, [">= 0".freeze])
  s.add_development_dependency(%q<pry-byebug>.freeze, [">= 0".freeze])
  s.add_development_dependency(%q<rack>.freeze, ["~> 2.0".freeze])
  s.add_development_dependency(%q<rackup>.freeze, [">= 0".freeze])
  s.add_development_dependency(%q<rake>.freeze, [">= 0".freeze])
  s.add_development_dependency(%q<rspec>.freeze, [">= 0".freeze])
  s.add_development_dependency(%q<rubocop>.freeze, ["~> 0.75.0".freeze])
  s.add_development_dependency(%q<rubocop-rspec>.freeze, [">= 0".freeze])
  s.add_development_dependency(%q<webrick>.freeze, [">= 0".freeze])
  s.add_development_dependency(%q<mutex_m>.freeze, [">= 0".freeze])
  s.add_development_dependency(%q<ostruct>.freeze, [">= 0".freeze])
end
