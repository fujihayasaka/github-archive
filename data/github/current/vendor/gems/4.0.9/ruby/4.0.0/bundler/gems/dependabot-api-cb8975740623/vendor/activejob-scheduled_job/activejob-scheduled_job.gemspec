# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name = "activejob-scheduled_job"
  spec.version = "0.1"
  spec.authors = ["@jurre"]
  spec.email = ["jurre@github.com"]

  spec.summary = "An ActiveJob extension for cluster-aware periodic scheduled jobs"

  spec.required_ruby_version = ">= 2.7.0"

  spec.add_runtime_dependency "activesupport", ">= 5.0.0", "< 9.0"
  spec.add_runtime_dependency "activejob", ">= 6.0", "< 9.0"

  spec.add_development_dependency "debug"
  spec.add_development_dependency "minitest"
  spec.add_development_dependency "rake"

  spec.files         = Dir.glob("**", base: "lib") + Dir.glob("activejob-scheduled_job.gemspec")
  spec.require_paths = %w[lib]
end
