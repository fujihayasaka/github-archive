# -*- encoding: utf-8 -*-
# stub: turboscan-client 1.0.0.pre.ef4288f ruby ruby/lib

Gem::Specification.new do |s|
  s.name = "turboscan-client".freeze
  s.version = "1.0.0.pre.ef4288f".freeze

  s.required_rubygems_version = Gem::Requirement.new("> 1.3.1".freeze) if s.respond_to? :required_rubygems_version=
  s.metadata = { "allowed_push_host" => "https://rubygems.pkg.github.com" } if s.respond_to? :metadata=
  s.require_paths = ["ruby/lib".freeze]
  s.authors = ["Kevin Sawicki".freeze]
  s.date = "2025-09-04"
  s.email = ["kevin@github.com".freeze]
  s.homepage = "https://github.com/github/turboscan".freeze
  s.rubygems_version = "3.3.27".freeze
  s.summary = "Twirp client for turboscan which is the backend that powers GitHub Code Scanning".freeze

  s.installed_by_version = "3.6.9".freeze

  s.specification_version = 4

  s.add_runtime_dependency(%q<google-protobuf>.freeze, [">= 3.14".freeze, "< 4.0".freeze])
  s.add_runtime_dependency(%q<twirp>.freeze, ["~> 1.10".freeze])
  s.add_runtime_dependency(%q<faraday>.freeze, [">= 0.15.4".freeze])
  s.add_development_dependency(%q<rspec>.freeze, ["~> 3.9".freeze])
  s.add_development_dependency(%q<vcr>.freeze, ["~> 6.2".freeze])
  s.add_development_dependency(%q<webmock>.freeze, ["~> 3.8".freeze])
  s.add_development_dependency(%q<rubocop-github>.freeze, [">= 0".freeze])
  s.add_development_dependency(%q<rubocop-performance>.freeze, [">= 0".freeze])
  s.add_development_dependency(%q<rubocop-rspec>.freeze, [">= 0".freeze])
  s.add_development_dependency(%q<pry>.freeze, [">= 0".freeze])
end
