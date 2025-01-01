# -*- encoding: utf-8 -*-
# stub: sigstore-proto 0.1.0 ruby lib

Gem::Specification.new do |s|
  s.name = "sigstore-proto".freeze
  s.version = "0.1.0".freeze

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.require_paths = ["lib".freeze]
  s.authors = ["Package Security".freeze]
  s.date = "2025-03-28"
  s.email = ["package-security@github.com".freeze]
  s.homepage = "https://github.com/github/sigstore-proto".freeze
  s.licenses = ["MIT".freeze]
  s.required_ruby_version = Gem::Requirement.new(">= 3.3.0".freeze)
  s.rubygems_version = "3.5.16".freeze
  s.summary = "Sigstore and in-toto protobuf messages".freeze

  s.installed_by_version = "3.6.9".freeze

  s.specification_version = 4

  s.add_runtime_dependency(%q<google-protobuf>.freeze, ["~> 3.5".freeze])
  s.add_runtime_dependency(%q<googleapis-common-protos-types>.freeze, ["= 1.7.0".freeze])
  s.add_development_dependency(%q<rake>.freeze, [">= 0".freeze])
  s.add_development_dependency(%q<minitest>.freeze, [">= 0".freeze])
  s.add_development_dependency(%q<pry>.freeze, [">= 0".freeze])
end
