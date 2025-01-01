# -*- encoding: utf-8 -*-
# stub: secure_headers 7.1.0 ruby lib

Gem::Specification.new do |s|
  s.name = "secure_headers".freeze
  s.version = "7.1.0".freeze

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.metadata = { "bug_tracker_uri" => "https://github.com/github/secure_headers/issues", "changelog_uri" => "https://github.com/github/secure_headers/blob/master/CHANGELOG.md", "documentation_uri" => "https://rubydoc.info/gems/secure_headers", "homepage_uri" => "https://github.com/github/secure_headers", "rubygems_mfa_required" => "true", "source_code_uri" => "https://github.com/github/secure_headers" } if s.respond_to? :metadata=
  s.require_paths = ["lib".freeze]
  s.authors = ["Neil Matatall".freeze]
  s.date = "2024-12-16"
  s.description = "Add easily configured security headers to responses\n    including content-security-policy, x-frame-options,\n    strict-transport-security, etc.".freeze
  s.email = ["neil.matatall@gmail.com".freeze]
  s.extra_rdoc_files = ["README.md".freeze, "CHANGELOG.md".freeze, "LICENSE".freeze]
  s.files = ["CHANGELOG.md".freeze, "LICENSE".freeze, "README.md".freeze]
  s.homepage = "https://github.com/github/secure_headers".freeze
  s.licenses = ["MIT".freeze]
  s.rubygems_version = "3.0.3.1".freeze
  s.summary = "Manages application of security headers with many safe defaults.".freeze

  s.installed_by_version = "3.6.7".freeze

  s.specification_version = 4

  s.add_development_dependency(%q<rake>.freeze, [">= 0".freeze])
end
