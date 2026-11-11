# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name = "turbocassette"
  spec.version = "1.0.0"

  spec.summary = "VCR Extension for contract testing"
  spec.homepage = "https://github.com/github/turbocassette"
  spec.authors = ["Marco Gario"]
  spec.email = ["marcogario@github.com"]

  # Prevent pushing this gem to RubyGems.org. To allow pushes either set the "allowed_push_host"
  # to allow pushing to a single host or delete this section to allow pushing to any host.
  if spec.respond_to?(:metadata)
    spec.metadata["allowed_push_host"] = "TODO: Set to 'http://mygemserver.com'"
  else
    raise "RubyGems 2.0 or newer is required to protect against " \
      "public gem pushes."
  end

  # Specify which files should be added to the gem when it is released.
  spec.files = [
    *Dir.glob("./*.gemspec"),
    *Dir.glob("ruby/**/*.rb"),
  ]
  spec.require_paths = ["ruby/lib"]

  spec.add_dependency "vcr", ">= 5.1"
  spec.add_dependency "webmock", ">= 3.8"
  spec.add_dependency "activesupport", ">= 6.0"
  spec.add_development_dependency "rspec", "~> 3.9"
  spec.add_development_dependency "pry", "~> 0.14"
end
