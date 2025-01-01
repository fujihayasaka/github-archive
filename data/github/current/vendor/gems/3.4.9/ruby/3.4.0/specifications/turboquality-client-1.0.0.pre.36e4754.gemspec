# -*- encoding: utf-8 -*-
# stub: turboquality-client 1.0.0.pre.36e4754 ruby ruby/lib

Gem::Specification.new do |s|
  s.name = "turboquality-client".freeze
  s.version = "1.0.0.pre.36e4754".freeze

  s.required_rubygems_version = Gem::Requirement.new("> 1.3.1".freeze) if s.respond_to? :required_rubygems_version=
  s.metadata = { "allowed_push_host" => "https://rubygems.pkg.github.com/github", "github_repo" => "ssh://github.com/github/turboquality" } if s.respond_to? :metadata=
  s.require_paths = ["ruby/lib".freeze]
  s.authors = ["Bogdana Vereha".freeze]
  s.date = "2025-08-26"
  s.email = ["bogdanap@github.com".freeze]
  s.homepage = "https://github.com/github/turboquality".freeze
  s.rubygems_version = "3.3.27".freeze
  s.summary = "Twirp client for turboquality".freeze

  s.installed_by_version = "3.6.9".freeze

  s.specification_version = 4

  s.add_runtime_dependency(%q<google-protobuf>.freeze, [">= 0".freeze])
  s.add_runtime_dependency(%q<twirp>.freeze, [">= 0".freeze])
  s.add_runtime_dependency(%q<faraday>.freeze, [">= 0".freeze])
  s.add_development_dependency(%q<vcr>.freeze, ["~> 6.2".freeze])
end
