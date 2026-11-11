# frozen_string_literal: true

require_relative "lib/github/telemetry/version"
Gem::Specification.new do |spec|
  spec.name          = "github-telemetry"
  spec.version       = GitHub::Telemetry::VERSION
  spec.authors       = ["GitHub Observability Team"]
  spec.email         = ["observability@github.com"]

  spec.summary       = "Centralized, default configurations for OpenTelemetry w/ Ruby at GitHub"
  spec.homepage      = "https://github.com/github/github-telemetry-ruby"
  spec.required_ruby_version = Gem::Requirement.new(">= 3.2.0")

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/releases"
  spec.metadata["bug_tracker_uri"] = "#{spec.homepage}/issues"
  spec.metadata["documentation_uri"] = "#{spec.homepage}/blob/main/README.md"
  spec.metadata["allowed_push_host"] = ENV.fetch("PUSH_HOST", "https://octofactory.githubapp.com/artifactory/api/gems/github-telemetry-ruby-gems-releases-local")
  spec.metadata["github_repo"] = "git@github.com:github/github-telemetry-ruby.git"

  spec.files = ::Dir.glob("lib/**/*.rb") +
               ::Dir.glob("*.md") +
               [".yardopts"] +
               ["github-telemetry.gemspec"]
  spec.require_paths = ["lib"]

  spec.license = "MIT"

  spec.add_dependency "opentelemetry-sdk", "~> 1.10", ">= 1.10.0"
  spec.add_dependency "opentelemetry-registry", "~> 0.4", ">= 0.4.0"
  spec.add_dependency "opentelemetry-exporter-otlp", "~> 0.26", ">= 0.26.1"
  spec.add_dependency "opentelemetry-instrumentation-rack", "~> 0.29", ">= 0.29.0"
  spec.add_dependency "opentelemetry-instrumentation-ethon", "~> 0.27", ">= 0.27.0"
  spec.add_dependency "opentelemetry-instrumentation-excon", "~> 0.27", ">= 0.27.0"
  spec.add_dependency "opentelemetry-instrumentation-faraday", "~> 0.31", ">= 0.31.0"
  spec.add_dependency "opentelemetry-instrumentation-graphql", "~> 0.31", ">= 0.31.2"
  spec.add_dependency "opentelemetry-instrumentation-net_http", "~> 0.27", ">= 0.27.0"
  spec.add_dependency "opentelemetry-instrumentation-rails", "~> 0.39", ">= 0.39.1"
  spec.add_dependency "opentelemetry-instrumentation-redis", "~> 0.28", ">= 0.28.0"
  spec.add_dependency "opentelemetry-instrumentation-ruby_kafka", "~> 0.24", ">= 0.24.0"
  spec.add_dependency "opentelemetry-instrumentation-trilogy", "~> 0.66", ">= 0.66.0"
  spec.add_dependency "opentelemetry-instrumentation-pg", "~> 0.35", ">= 0.35.0"
  spec.add_dependency "semantic_logger", "~> 4.17"
end
