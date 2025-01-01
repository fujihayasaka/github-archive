# frozen_string_literal: true

require File.expand_path("lib/vexi_management/version", __dir__)

Gem::Specification.new do |s|
  s.name                  = "vexi_management"
  s.version               = VexiManagement::VERSION
  s.date                  = "2024-02-06"
  s.summary               = "Vexi Management is a Ruby Client for feature flag management operations"
  s.description           = 'Vexi is short for "vexillology" which is the study of flags.'
  s.authors               = ["github/feature-management"]
  s.files                 = Dir["lib/**/*.rb"]
  s.homepage              = "http://www.github.com/github/feature-management-client-ruby"
  s.license               = "Nonstandard"
  s.metadata              = { "github_repo" => "ssh://github.com/github/feature-management-client-ruby" }
  s.required_ruby_version = ">= 3.0.0" # specify the minimum Ruby version that your gem supports

  s.add_runtime_dependency "sorbet-runtime", "~> 0.5"
  s.add_runtime_dependency "vexi"
end
