# frozen_string_literal: true

require File.expand_path("lib/vexi/version", __dir__)

Gem::Specification.new do |s|
  s.name                  = "vexi-development"
  s.version               = Vexi::VERSION
  s.date                  = "2022-01-01"
  s.summary               = "This is the development version for Vexi and not intended for production use."
  s.description           = 'Vexi is short for "vexillology" which is the study of flags.'
  s.authors               = ["github/feature-management"]
  s.files                 = Dir["lib/**/*.rb"]
  s.homepage              = "http://www.github.com/github/feature-management-client-ruby"
  s.license               = "Nonstandard"
  s.metadata              = { "github_repo" => "ssh://github.com/github/feature-management-client-ruby" }
  s.required_ruby_version = ">= 3.0.0" # specify the minimum Ruby version that your gem supports

  s.add_runtime_dependency "activesupport", ">=7.0"
  s.add_runtime_dependency "feature_management_feature_flags", ">= 1.6", "< 1.8"
  s.add_runtime_dependency "sorbet-runtime"
  s.add_runtime_dependency "fnv", "0.2.0"
  s.add_runtime_dependency "zache", "0.13.2"
end
