# -*- encoding: utf-8 -*-
# stub: osslicensecompliance-client 0.3.0.pre.4313a7f ruby lib

Gem::Specification.new do |s|
  s.name = "osslicensecompliance-client".freeze
  s.version = "0.3.0.pre.4313a7f".freeze

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.require_paths = ["lib".freeze]
  s.authors = ["GitHub".freeze]
  s.date = "1980-01-02"
  s.files = ["./osslicensecompliance-client.gemspec".freeze]
  s.homepage = "https://github.com/github/osslicensecompliance/tree/main/ruby".freeze
  s.licenses = ["Nonstandard".freeze]
  s.rubygems_version = "3.6.9".freeze
  s.summary = "Generated Twirp client code for github/osslicensecompliance service.".freeze

  s.installed_by_version = "3.6.9".freeze

  s.specification_version = 4

  s.add_runtime_dependency(%q<google-protobuf>.freeze, [">= 3.14".freeze, "< 4.0".freeze])
  s.add_runtime_dependency(%q<twirp>.freeze, ["~> 1.10".freeze])
  s.add_runtime_dependency(%q<faraday>.freeze, [">= 0.15.4".freeze])
  s.add_development_dependency(%q<bundler>.freeze, [">= 0".freeze])
  s.add_development_dependency(%q<minitest>.freeze, ["~> 5.25".freeze])
  s.add_development_dependency(%q<rake>.freeze, [">= 0".freeze])
end
