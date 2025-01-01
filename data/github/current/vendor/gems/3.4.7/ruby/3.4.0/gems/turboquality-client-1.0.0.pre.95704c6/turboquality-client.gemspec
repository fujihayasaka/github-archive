# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name = "turboquality-client"
  spec.version = begin
    version = "1.0.0"
    sha = `git rev-parse --short HEAD`.strip # Get short commit SHA
    "#{version}-#{sha}"
  rescue
    version # Fallback to just the version if Git is not available
  end

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
