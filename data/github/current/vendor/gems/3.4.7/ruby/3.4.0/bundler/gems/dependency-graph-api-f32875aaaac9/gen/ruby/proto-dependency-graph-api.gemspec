# -*- encoding: utf-8 -*-
# stub: proto-dependency-graph-api 1.0.0 ruby lib

Gem::Specification.new do |s|
  s.name = "proto-dependency-graph-api".freeze
  s.version = "1.0.0".freeze

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.require_paths = ["lib".freeze]
  s.authors = ["GitHub".freeze]
  s.date = "1980-01-02"
  s.files = ["lib/proto-dependency-graph-api.rb".freeze, "lib/proto/dependency-graph-api/v1/dependency_graph_api_pb.rb".freeze, "lib/proto/dependency-graph-api/v1/dependency_graph_api_twirp.rb".freeze]
  s.homepage = "https://github.com/github/dependency-graph-api/tree/master/gen/ruby".freeze
  s.licenses = ["Nonstandard".freeze]
  s.rubygems_version = "3.6.7".freeze
  s.summary = "Generated client/server code for github/dependency-graph-api".freeze

  s.installed_by_version = "3.6.9".freeze

  s.specification_version = 4

  s.add_runtime_dependency(%q<twirp>.freeze, ["~> 1.1".freeze])
  s.add_development_dependency(%q<bundler>.freeze, [">= 0".freeze])
  s.add_development_dependency(%q<minitest>.freeze, ["~> 5.0".freeze])
  s.add_development_dependency(%q<rake>.freeze, [">= 0".freeze])
end
