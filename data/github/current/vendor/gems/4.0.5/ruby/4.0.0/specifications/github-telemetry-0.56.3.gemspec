# -*- encoding: utf-8 -*-
# stub: github-telemetry 0.56.3 ruby lib

Gem::Specification.new do |s|
  s.name = "github-telemetry".freeze
  s.version = "0.56.3".freeze

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.metadata = { "allowed_push_host" => "https://rubygems.pkg.github.com/github", "bug_tracker_uri" => "https://github.com/github/github-telemetry-ruby/issues", "changelog_uri" => "https://github.com/github/github-telemetry-ruby/releases", "documentation_uri" => "https://github.com/github/github-telemetry-ruby/blob/main/README.md", "github_repo" => "git@github.com:github/github-telemetry-ruby.git", "homepage_uri" => "https://github.com/github/github-telemetry-ruby", "source_code_uri" => "https://github.com/github/github-telemetry-ruby" } if s.respond_to? :metadata=
  s.require_paths = ["lib".freeze]
  s.authors = ["GitHub Observability Team".freeze]
  s.date = "1980-01-02"
  s.email = ["observability@github.com".freeze]
  s.homepage = "https://github.com/github/github-telemetry-ruby".freeze
  s.licenses = ["MIT".freeze]
  s.required_ruby_version = Gem::Requirement.new(">= 3.2.0".freeze)
  s.rubygems_version = "4.0.6".freeze
  s.summary = "Centralized, default configurations for OpenTelemetry w/ Ruby at GitHub".freeze

  s.installed_by_version = "4.0.10".freeze

  s.specification_version = 4

  s.add_runtime_dependency(%q<opentelemetry-sdk>.freeze, ["~> 1.10".freeze, ">= 1.10.0".freeze])
  s.add_runtime_dependency(%q<opentelemetry-registry>.freeze, ["~> 0.4".freeze, ">= 0.4.0".freeze])
  s.add_runtime_dependency(%q<opentelemetry-exporter-otlp>.freeze, ["~> 0.26".freeze, ">= 0.26.1".freeze])
  s.add_runtime_dependency(%q<opentelemetry-instrumentation-rack>.freeze, ["~> 0.29".freeze, ">= 0.29.0".freeze])
  s.add_runtime_dependency(%q<opentelemetry-instrumentation-ethon>.freeze, ["~> 0.27".freeze, ">= 0.27.0".freeze])
  s.add_runtime_dependency(%q<opentelemetry-instrumentation-excon>.freeze, ["~> 0.27".freeze, ">= 0.27.0".freeze])
  s.add_runtime_dependency(%q<opentelemetry-instrumentation-faraday>.freeze, ["~> 0.31".freeze, ">= 0.31.0".freeze])
  s.add_runtime_dependency(%q<opentelemetry-instrumentation-graphql>.freeze, ["~> 0.31".freeze, ">= 0.31.2".freeze])
  s.add_runtime_dependency(%q<opentelemetry-instrumentation-net_http>.freeze, ["~> 0.27".freeze, ">= 0.27.0".freeze])
  s.add_runtime_dependency(%q<opentelemetry-instrumentation-rails>.freeze, ["~> 0.39".freeze, ">= 0.39.1".freeze])
  s.add_runtime_dependency(%q<opentelemetry-instrumentation-redis>.freeze, ["~> 0.28".freeze, ">= 0.28.0".freeze])
  s.add_runtime_dependency(%q<opentelemetry-instrumentation-ruby_kafka>.freeze, ["~> 0.24".freeze, ">= 0.24.0".freeze])
  s.add_runtime_dependency(%q<opentelemetry-instrumentation-trilogy>.freeze, ["~> 0.66".freeze, ">= 0.66.0".freeze])
  s.add_runtime_dependency(%q<opentelemetry-instrumentation-pg>.freeze, ["~> 0.35".freeze, ">= 0.35.0".freeze])
  s.add_runtime_dependency(%q<semantic_logger>.freeze, ["~> 4.17".freeze])
end
