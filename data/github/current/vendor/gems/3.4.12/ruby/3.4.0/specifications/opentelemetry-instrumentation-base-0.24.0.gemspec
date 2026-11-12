# -*- encoding: utf-8 -*-
# stub: opentelemetry-instrumentation-base 0.24.0 ruby lib

Gem::Specification.new do |s|
  s.name = "opentelemetry-instrumentation-base".freeze
  s.version = "0.24.0".freeze

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.metadata = { "bug_tracker_uri" => "https://github.com/open-telemetry/opentelemetry-ruby-contrib/issues", "changelog_uri" => "https://rubydoc.info/gems/opentelemetry-instrumentation-base/0.24.0/file/CHANGELOG.md", "documentation_uri" => "https://rubydoc.info/gems/opentelemetry-instrumentation-base/0.24.0", "source_code_uri" => "https://github.com/open-telemetry/opentelemetry-ruby-contrib/tree/main/instrumentation/base" } if s.respond_to? :metadata=
  s.require_paths = ["lib".freeze]
  s.authors = ["OpenTelemetry Authors".freeze]
  s.date = "2025-09-30"
  s.description = "Instrumentation Base for the OpenTelemetry framework".freeze
  s.email = ["cncf-opentelemetry-contributors@lists.cncf.io".freeze]
  s.homepage = "https://github.com/open-telemetry/opentelemetry-ruby-contrib".freeze
  s.licenses = ["Apache-2.0".freeze]
  s.required_ruby_version = Gem::Requirement.new(">= 3.1".freeze)
  s.rubygems_version = "3.3.27".freeze
  s.summary = "Instrumentation Base for the OpenTelemetry framework".freeze

  s.installed_by_version = "3.6.9".freeze

  s.specification_version = 4

  s.add_runtime_dependency(%q<opentelemetry-api>.freeze, ["~> 1.7".freeze])
  s.add_runtime_dependency(%q<opentelemetry-common>.freeze, ["~> 0.21".freeze])
  s.add_runtime_dependency(%q<opentelemetry-registry>.freeze, ["~> 0.1".freeze])
end
