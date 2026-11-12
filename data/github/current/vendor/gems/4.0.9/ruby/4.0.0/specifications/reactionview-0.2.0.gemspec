# -*- encoding: utf-8 -*-
# stub: reactionview 0.2.0 ruby lib

Gem::Specification.new do |s|
  s.name = "reactionview".freeze
  s.version = "0.2.0".freeze

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.metadata = { "changelog_uri" => "https://github.com/marcoroth/reactionview/releases", "homepage_uri" => "https://reactionview.dev", "rubygems_mfa_required" => "true", "source_code_uri" => "https://github.com/marcoroth/reactionview" } if s.respond_to? :metadata=
  s.require_paths = ["lib".freeze]
  s.authors = ["Marco Roth".freeze]
  s.bindir = "exe".freeze
  s.date = "2025-12-04"
  s.description = "An ActionView-compatible ERB engine with modern DX - re-imagined with Herb.".freeze
  s.email = ["marco.roth@intergga.ch".freeze]
  s.homepage = "https://reactionview.dev".freeze
  s.licenses = ["MIT".freeze]
  s.required_ruby_version = Gem::Requirement.new(">= 3.2.0".freeze)
  s.rubygems_version = "3.6.2".freeze
  s.summary = "An ActionView-compatible ERB engine with modern DX - re-imagined with Herb.".freeze

  s.installed_by_version = "4.0.20".freeze

  s.specification_version = 4

  s.add_runtime_dependency(%q<actionview>.freeze, [">= 7.0".freeze])
  s.add_runtime_dependency(%q<herb>.freeze, [">= 0.8.0".freeze, "< 1.0.0".freeze])
end
