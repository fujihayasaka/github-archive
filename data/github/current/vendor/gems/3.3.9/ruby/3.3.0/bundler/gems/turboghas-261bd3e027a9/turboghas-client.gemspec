# -*- encoding: utf-8 -*-
# stub: turboghas-client 1.0.0 ruby ruby/lib

Gem::Specification.new do |s|
  s.name = "turboghas-client".freeze
  s.version = "1.0.0".freeze

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.metadata = { "allowed_push_host" => "https://rubygems.pkg.github.com/github", "github_repo" => "ssh://github.com/github/turboghas" } if s.respond_to? :metadata=
  s.require_paths = ["ruby/lib".freeze]
  s.authors = ["Simon Engledew".freeze]
  s.date = "2025-08-25"
  s.email = ["simon-engledew@github.com".freeze]
  s.files = ["./turboghas-client.gemspec".freeze, "ruby/cassettes/get-active-committers.enterprise.yml".freeze, "ruby/cassettes/get-active-committers.yml".freeze, "ruby/cassettes/get-additional-committers-per-repository-enterprise-users.yml".freeze, "ruby/cassettes/get-additional-committers-per-repository.yml".freeze, "ruby/cassettes/get-committers-for-business-enterprise-users.yml".freeze, "ruby/cassettes/get-committers-for-business.enterprise.yml".freeze, "ruby/cassettes/get-committers-for-business.yml".freeze, "ruby/cassettes/get-committers-for-owner.enterprise.yml".freeze, "ruby/cassettes/get-committers-for-owner.yml".freeze, "ruby/cassettes/get-committers-for-user-owner.enterprise.yml".freeze, "ruby/cassettes/get-committers-for-user-owner.yml".freeze, "ruby/cassettes/get-enterprise-users.enterprise.yml".freeze, "ruby/cassettes/get-enterprise-users.yml".freeze, "ruby/cassettes/get-meter-emissions-with-additional-users.yml".freeze, "ruby/cassettes/get-meter-emissions.yml".freeze, "ruby/cassettes/get-organizations.enterprise.yml".freeze, "ruby/cassettes/get-organizations.yml".freeze, "ruby/cassettes/get-repositories.enterprise.yml".freeze, "ruby/cassettes/get-repositories.yml".freeze, "ruby/cassettes/get-summary.enterprise.yml".freeze, "ruby/cassettes/get-summary.yml".freeze, "ruby/lib/entity_type_pb.rb".freeze, "ruby/lib/turboghas.rb".freeze, "ruby/lib/turboghas_pb.rb".freeze, "ruby/lib/turboghas_twirp.rb".freeze, "ruby/lib/turboghas_vcr.rb".freeze]
  s.homepage = "https://github.com/github/turboghas".freeze
  s.rubygems_version = "3.5.22".freeze
  s.summary = "Twirp client for turboghas".freeze

  s.installed_by_version = "3.5.22".freeze

  s.specification_version = 4

  s.add_runtime_dependency(%q<google-protobuf>.freeze, [">= 0".freeze])
  s.add_runtime_dependency(%q<twirp>.freeze, [">= 0".freeze])
  s.add_runtime_dependency(%q<faraday>.freeze, [">= 0".freeze])
  s.add_runtime_dependency(%q<monolith-twirp-code_scanning-turboghas>.freeze, [">= 0".freeze])
  s.add_development_dependency(%q<vcr>.freeze, ["~> 5.1".freeze])
end
