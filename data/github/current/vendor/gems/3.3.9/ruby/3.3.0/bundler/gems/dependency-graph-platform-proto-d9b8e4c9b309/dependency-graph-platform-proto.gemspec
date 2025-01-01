# -*- encoding: utf-8 -*-
# stub: dependency-graph-platform-proto 0.0.3 ruby gen/ruby/lib

Gem::Specification.new do |s|
  s.name = "dependency-graph-platform-proto".freeze
  s.version = "0.0.3".freeze

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.require_paths = ["gen/ruby/lib".freeze]
  s.authors = ["GitHub".freeze]
  s.date = "2025-10-24"
  s.files = ["gen/ruby/lib/alerting/v1/alerting_api_pb.rb".freeze, "gen/ruby/lib/alerting/v1/alerting_api_twirp.rb".freeze, "gen/ruby/lib/dependency-graph-platform-proto.rb".freeze, "gen/ruby/lib/health/v1/health_api_pb.rb".freeze, "gen/ruby/lib/health/v1/health_api_twirp.rb".freeze, "gen/ruby/lib/reachability/v1/dependencies_api_pb.rb".freeze, "gen/ruby/lib/reachability/v1/dependencies_api_twirp.rb".freeze, "gen/ruby/lib/repo-insights/v1/repo_insights_api_pb.rb".freeze, "gen/ruby/lib/repo-insights/v1/repo_insights_api_twirp.rb".freeze, "gen/ruby/lib/sbom/v1/sbom_api_pb.rb".freeze, "gen/ruby/lib/sbom/v1/sbom_api_twirp.rb".freeze, "gen/ruby/lib/types/v1/dependency_pb.rb".freeze, "gen/ruby/lib/types/v1/dependency_twirp.rb".freeze, "gen/ruby/lib/types/v1/manifest_pb.rb".freeze, "gen/ruby/lib/types/v1/manifest_twirp.rb".freeze, "gen/ruby/lib/v1/experimental/dependencies_pb.rb".freeze, "gen/ruby/lib/v1/experimental/dependencies_twirp.rb".freeze]
  s.homepage = "https://github.com/github/dependency-graph-platform-proto".freeze
  s.licenses = ["Nonstandard".freeze]
  s.rubygems_version = "3.5.22".freeze
  s.summary = "Generated Twirp client code for Dependency Graph Platform service.".freeze

  s.installed_by_version = "3.5.22".freeze

  s.specification_version = 4

  s.add_runtime_dependency(%q<twirp>.freeze, ["~> 1.7".freeze])
  s.add_development_dependency(%q<bundler>.freeze, [">= 0".freeze])
  s.add_development_dependency(%q<minitest>.freeze, ["~> 5.2".freeze])
  s.add_development_dependency(%q<rake>.freeze, [">= 0".freeze])
end
