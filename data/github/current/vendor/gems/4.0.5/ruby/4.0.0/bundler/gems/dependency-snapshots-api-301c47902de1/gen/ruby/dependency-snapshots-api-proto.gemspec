# -*- encoding: utf-8 -*-
# stub: dependency-snapshots-api-proto 0.0.1 ruby lib

Gem::Specification.new do |s|
  s.name = "dependency-snapshots-api-proto".freeze
  s.version = "0.0.1".freeze

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.require_paths = ["lib".freeze]
  s.authors = ["GitHub".freeze]
  s.date = "1980-01-02"
  s.files = ["lib/buf/validate/validate_pb.rb".freeze, "lib/dependabot_pb.rb".freeze, "lib/dependabot_twirp.rb".freeze, "lib/dependencies_pb.rb".freeze, "lib/dependencies_twirp.rb".freeze, "lib/dependency-snapshots-api-proto.rb".freeze, "lib/diagnostic_pb.rb".freeze, "lib/diagnostic_twirp.rb".freeze, "lib/entities/dependabot_event_pb.rb".freeze, "lib/entities/dependabot_event_twirp.rb".freeze, "lib/entities/dependency_pb.rb".freeze, "lib/entities/dependency_twirp.rb".freeze, "lib/entities/manifest_pb.rb".freeze, "lib/entities/manifest_twirp.rb".freeze, "lib/entities/pull_request_pb.rb".freeze, "lib/entities/pull_request_twirp.rb".freeze, "lib/entities/push_pb.rb".freeze, "lib/entities/push_twirp.rb".freeze, "lib/entities/repository_pb.rb".freeze, "lib/entities/repository_twirp.rb".freeze, "lib/entities/snapshot_pb.rb".freeze, "lib/entities/snapshot_twirp.rb".freeze, "lib/entities/user_pb.rb".freeze, "lib/entities/user_twirp.rb".freeze, "lib/snapshots_pb.rb".freeze, "lib/snapshots_twirp.rb".freeze]
  s.homepage = "https://github.com/github/dependency-snapshots-api/tree/main/gen/ruby".freeze
  s.licenses = ["Nonstandard".freeze]
  s.rubygems_version = "4.0.3".freeze
  s.summary = "Generated client code for Dependency Snapshots API.".freeze

  s.installed_by_version = "4.0.10".freeze

  s.specification_version = 4

  s.add_runtime_dependency(%q<twirp>.freeze, ["~> 1.1".freeze])
  s.add_development_dependency(%q<bundler>.freeze, [">= 0".freeze])
  s.add_development_dependency(%q<minitest>.freeze, ["~> 5.0".freeze])
  s.add_development_dependency(%q<rake>.freeze, [">= 0".freeze])
end
