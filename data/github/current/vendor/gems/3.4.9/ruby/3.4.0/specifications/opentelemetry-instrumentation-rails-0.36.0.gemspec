# -*- encoding: utf-8 -*-
# stub: opentelemetry-instrumentation-rails 0.36.0 ruby lib

Gem::Specification.new do |s|
  s.name = "opentelemetry-instrumentation-rails".freeze
  s.version = "0.36.0".freeze

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.metadata = { "source_code_uri" => "https://github.com/open-telemetry/opentelemetry-ruby-contrib/tree/main/instrumentation/rails" } if s.respond_to? :metadata=
  s.require_paths = ["lib".freeze]
  s.authors = ["OpenTelemetry Authors".freeze]
  s.date = "2025-02-04"
  s.description = "Rails instrumentation for the OpenTelemetry framework".freeze
  s.email = ["cncf-opentelemetry-contributors@lists.cncf.io".freeze]
  s.homepage = "https://github.com/open-telemetry/opentelemetry-ruby-contrib".freeze
  s.licenses = ["Apache-2.0".freeze]
  s.post_install_message = "".freeze
  s.required_ruby_version = Gem::Requirement.new(">= 3.1".freeze)
  s.rubygems_version = "3.3.27".freeze
  s.summary = "Rails instrumentation for the OpenTelemetry framework".freeze

  s.installed_by_version = "3.6.9".freeze

  s.specification_version = 4

  s.add_runtime_dependency(%q<opentelemetry-api>.freeze, ["~> 1.0".freeze])
  s.add_runtime_dependency(%q<opentelemetry-instrumentation-action_mailer>.freeze, ["~> 0.4.0".freeze])
  s.add_runtime_dependency(%q<opentelemetry-instrumentation-action_pack>.freeze, ["~> 0.12.0".freeze])
  s.add_runtime_dependency(%q<opentelemetry-instrumentation-action_view>.freeze, ["~> 0.9.0".freeze])
  s.add_runtime_dependency(%q<opentelemetry-instrumentation-active_job>.freeze, ["~> 0.8.0".freeze])
  s.add_runtime_dependency(%q<opentelemetry-instrumentation-active_record>.freeze, ["~> 0.9.0".freeze])
  s.add_runtime_dependency(%q<opentelemetry-instrumentation-active_storage>.freeze, ["~> 0.1.0".freeze])
  s.add_runtime_dependency(%q<opentelemetry-instrumentation-active_support>.freeze, ["~> 0.8.0".freeze])
  s.add_runtime_dependency(%q<opentelemetry-instrumentation-base>.freeze, ["~> 0.23.0".freeze])
  s.add_runtime_dependency(%q<opentelemetry-instrumentation-concurrent_ruby>.freeze, ["~> 0.22.0".freeze])
  s.add_development_dependency(%q<appraisal>.freeze, ["~> 2.5".freeze])
  s.add_development_dependency(%q<bundler>.freeze, ["~> 2.4".freeze])
  s.add_development_dependency(%q<minitest>.freeze, ["~> 5.0".freeze])
  s.add_development_dependency(%q<opentelemetry-sdk>.freeze, ["~> 1.1".freeze])
  s.add_development_dependency(%q<opentelemetry-test-helpers>.freeze, ["~> 0.3".freeze])
  s.add_development_dependency(%q<rack-test>.freeze, ["~> 2.1.0".freeze])
  s.add_development_dependency(%q<rake>.freeze, ["~> 13.0".freeze])
  s.add_development_dependency(%q<rubocop>.freeze, ["~> 1.71.0".freeze])
  s.add_development_dependency(%q<rubocop-performance>.freeze, ["~> 1.23.0".freeze])
  s.add_development_dependency(%q<simplecov>.freeze, ["~> 0.22.0".freeze])
  s.add_development_dependency(%q<webmock>.freeze, ["~> 3.24.0".freeze])
  s.add_development_dependency(%q<yard>.freeze, ["~> 0.9".freeze])
end
