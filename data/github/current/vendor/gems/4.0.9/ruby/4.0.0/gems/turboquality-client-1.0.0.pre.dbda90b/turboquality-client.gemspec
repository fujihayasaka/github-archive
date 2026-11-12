# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name = "turboquality-client"
  # Base version for the gem. In CI/publish workflows, set GEM_SHA to append
  # a unique suffix (e.g., "1.0.0-<sha>") so that each build has a distinct
  # version. For local development or installation, GEM_SHA can be omitted
  # and the version will remain "1.0.0".
  version = "1.0.0"
  sha = ENV["GEM_SHA"]
  spec.version = sha ? "#{version}-#{sha}" : version

  spec.summary = "Twirp client for turboquality"
  spec.homepage = "https://github.com/github/turboquality"
  spec.authors = ["Bogdana Vereha"]
  spec.email = ["bogdanap@github.com"]
  spec.metadata["github_repo"] = "ssh://github.com/github/turboquality"
  spec.metadata["allowed_push_host"] = "https://rubygems.pkg.github.com/github"

  spec.files = [
    *Dir.glob("./*.gemspec"),
    *Dir.glob("ruby/**/*.rb"),
    *Dir.glob("ruby/cassettes/**/*.yml"),
  ]
  spec.require_paths = ["ruby/lib"]

  spec.add_runtime_dependency "google-protobuf"
  spec.add_runtime_dependency "twirp"
  spec.add_runtime_dependency "faraday"

  spec.add_development_dependency "vcr", "~> 6.2"
end
