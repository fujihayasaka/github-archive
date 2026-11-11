# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name = "turboghas-client"
  spec.version = begin
    version = "1.0.0"
    sha = `git rev-parse --short HEAD`.strip # Get short commit SHA
    "#{version}-#{sha}"
  rescue
    version # Fallback to just the version if Git is not available
  end

  begin
    # include sha if possible
    spec.metadata["commit"] = `git rev-parse HEAD`.strip
  rescue
    nil
  end
  spec.summary = "Twirp client for turboghas"
  spec.homepage = "https://github.com/github/turboghas"
  spec.authors = ["Simon Engledew"]
  spec.email = ["simon-engledew@github.com"]
  spec.metadata["github_repo"] = "ssh://github.com/github/turboghas"
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
  spec.add_runtime_dependency "monolith-twirp-code_scanning-turboghas"

  spec.add_development_dependency "vcr", "~> 5.1"
end
