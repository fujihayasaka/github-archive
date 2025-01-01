# -*- encoding: utf-8 -*-
# stub: vonage-jwt 0.2.0 ruby lib

Gem::Specification.new do |s|
  s.name = "vonage-jwt".freeze
  s.version = "0.2.0".freeze

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.metadata = { "bug_tracker_uri" => "https://github.com/Vonage/vonage-jwt-ruby/issues", "changelog_uri" => "https://github.com/Vonage/vonage-jwt-ruby/blob/main/CHANGES.md", "documentation_uri" => "https://rubydoc.info/github/Vonage/vonage-jwt-ruby", "homepage" => "https://github.com/Vonage/vonage-jwt-ruby", "source_code_uri" => "https://github.com/Vonage/vonage-jwt-ruby" } if s.respond_to? :metadata=
  s.require_paths = ["lib".freeze]
  s.authors = ["Vonage".freeze]
  s.date = "2023-10-26"
  s.description = "Vonage JWT Generator for Ruby".freeze
  s.email = ["devrel@vonage.com".freeze]
  s.homepage = "https://github.com/Vonage/vonage-jwt-ruby".freeze
  s.licenses = ["MIT".freeze]
  s.required_ruby_version = Gem::Requirement.new(">= 2.5.0".freeze)
  s.rubygems_version = "3.2.3".freeze
  s.summary = "This is the Ruby client library to generate Vonage JSON Web Tokens (JWTs).".freeze

  s.installed_by_version = "3.6.9".freeze

  s.specification_version = 4

  s.add_runtime_dependency(%q<jwt>.freeze, ["~> 2".freeze])
end
