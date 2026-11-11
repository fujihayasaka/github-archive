# -*- encoding: utf-8 -*-
# stub: configsd-client 0.1.0 ruby lib

Gem::Specification.new do |s|
  s.name = "configsd-client".freeze
  s.version = "0.1.0".freeze

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.metadata = { "allowed_push_host" => "https://rubygems.pkg.github.com/github", "homepage_uri" => "https://github.com/github/configsd", "source_code_uri" => "https://github.com/github/configsd" } if s.respond_to? :metadata=
  s.require_paths = ["lib".freeze]
  s.authors = ["Jake Brady".freeze]
  s.bindir = "exe".freeze
  s.date = "1980-01-02"
  s.description = "Ruby client for the configsd twirp service".freeze
  s.email = ["27361+jakebrady5@users.noreply.github.com".freeze]
  s.files = ["lib/configs.rb".freeze, "lib/configs/client.rb".freeze, "lib/configs/entry.rb".freeze, "lib/configs/errors.rb".freeze, "lib/configs/proto/configs/configs_pb.rb".freeze, "lib/configs/proto/configs/configs_twirp.rb".freeze, "lib/configs/version.rb".freeze]
  s.homepage = "https://github.com/github/configsd".freeze
  s.required_ruby_version = Gem::Requirement.new(">= 3.4.0".freeze)
  s.rubygems_version = "3.6.9".freeze
  s.summary = "Ruby client for the configsd twirp service".freeze

  s.installed_by_version = "4.0.3".freeze

  s.specification_version = 4

  s.add_runtime_dependency(%q<faraday>.freeze, ["~> 1.10.4".freeze])
  s.add_runtime_dependency(%q<twirp>.freeze, ["~> 1.10.0".freeze])
  s.add_runtime_dependency(%q<rack>.freeze, ["~> 2.2".freeze])
  s.add_development_dependency(%q<rake>.freeze, ["~> 13.0".freeze])
  s.add_development_dependency(%q<minitest>.freeze, ["~> 5.0".freeze])
  s.add_development_dependency(%q<minitest-stub-const>.freeze, [">= 0".freeze])
  s.add_development_dependency(%q<mocha>.freeze, ["~> 2.7.1".freeze])
  s.add_development_dependency(%q<debug>.freeze, ["~> 1.9".freeze])
end
