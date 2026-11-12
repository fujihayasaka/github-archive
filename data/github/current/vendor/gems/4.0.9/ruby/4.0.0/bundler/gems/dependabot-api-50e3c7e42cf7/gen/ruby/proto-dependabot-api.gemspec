# -*- encoding: utf-8 -*-
# stub: proto-dependabot-api 1.2.1 ruby lib

Gem::Specification.new do |s|
  s.name = "proto-dependabot-api".freeze
  s.version = "1.2.1".freeze

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.require_paths = ["lib".freeze]
  s.authors = ["GitHub".freeze]
  s.date = "1980-01-02"
  s.files = ["lib/proto-dependabot-api.rb".freeze, "lib/proto/dependabot-api/v1/dependabot_api_pb.rb".freeze, "lib/proto/dependabot-api/v1/dependabot_api_twirp.rb".freeze, "lib/proto/dependabot-api/v1/suggested_fixes_pb.rb".freeze, "lib/proto/dependabot-api/v1/suggested_fixes_twirp.rb".freeze, "lib/proto/dependabot-api/version.rb".freeze]
  s.homepage = "https://github.com/github/dependabot-api/tree/main/gen/ruby".freeze
  s.licenses = ["Nonstandard".freeze]
  s.rubygems_version = "4.0.3".freeze
  s.summary = "Generated client/server code for github/dependabot-api".freeze

  s.installed_by_version = "4.0.20".freeze

  s.specification_version = 4

  s.add_runtime_dependency(%q<twirp>.freeze, ["~> 1.1".freeze])
  s.add_development_dependency(%q<bundler>.freeze, [">= 0".freeze])
  s.add_development_dependency(%q<minitest>.freeze, ["~> 5.0".freeze])
  s.add_development_dependency(%q<rake>.freeze, [">= 0".freeze])
end
