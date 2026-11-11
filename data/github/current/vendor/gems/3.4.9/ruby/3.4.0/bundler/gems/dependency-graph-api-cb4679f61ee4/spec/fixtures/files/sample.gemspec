Gem::Specification.new do |s|
  s.name    = "Just a gem spec"
  s.summary = "A gem spec for testing"
  s.version = "0.0.1"
  s.homepage = "url
  s.authors = %w[look josedab"]

  s.add_runtime_dependency "twirp", "~> 1.1"
  s.add_runtime_dependency "resilient", "~> 0.4.0" 

  s.add_development_dependency "google-protobuf", "~> 3.9.1"

  s.files = Dir["ruby/**/*.rb", "proto/**/*.proto"]
end
