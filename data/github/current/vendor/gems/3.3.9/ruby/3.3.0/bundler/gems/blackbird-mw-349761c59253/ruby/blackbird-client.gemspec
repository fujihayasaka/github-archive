# -*- encoding: utf-8 -*-
# stub: blackbird-client 0.1.1 ruby lib

Gem::Specification.new do |s|
  s.name = "blackbird-client".freeze
  s.version = "0.1.1".freeze

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.require_paths = ["lib".freeze]
  s.authors = ["Michelle Lemons".freeze]
  s.date = "2025-08-21"
  s.files = ["lib/admin/v1/service_pb.rb".freeze, "lib/admin/v1/service_twirp.rb".freeze, "lib/blackbird-client.rb".freeze, "lib/hydro/schemas/blackbird/v0/entities/accessible_resources_pb.rb".freeze, "lib/hydro/schemas/blackbird/v0/entities/accessible_resources_twirp.rb".freeze, "lib/hydro/schemas/blackbird/v0/entities/epoch_mode_pb.rb".freeze, "lib/hydro/schemas/blackbird/v0/entities/epoch_mode_twirp.rb".freeze, "lib/hydro/schemas/blackbird/v0/entities/symbol_kind_pb.rb".freeze, "lib/hydro/schemas/blackbird/v0/entities/symbol_kind_twirp.rb".freeze, "lib/query/v1/aleph_pb.rb".freeze, "lib/query/v1/aleph_twirp.rb".freeze, "lib/query/v1/facets_pb.rb".freeze, "lib/query/v1/facets_twirp.rb".freeze, "lib/query/v1/git_document_match_pb.rb".freeze, "lib/query/v1/git_document_match_twirp.rb".freeze, "lib/query/v1/scoring_info_pb.rb".freeze, "lib/query/v1/scoring_info_twirp.rb".freeze, "lib/query/v1/search_result_pb.rb".freeze, "lib/query/v1/search_result_twirp.rb".freeze, "lib/query/v1/service_pb.rb".freeze, "lib/query/v1/service_twirp.rb".freeze, "lib/query/v1/shard_pb.rb".freeze, "lib/query/v1/shard_twirp.rb".freeze, "lib/query/v1/symbol_pb.rb".freeze, "lib/query/v1/symbol_twirp.rb".freeze, "lib/version.rb".freeze]
  s.homepage = "https://github.com/github/blackbird-mw".freeze
  s.rubygems_version = "3.5.22".freeze
  s.summary = "Ruby client for blackbird service".freeze

  s.installed_by_version = "3.5.22".freeze

  s.specification_version = 4

  s.add_runtime_dependency(%q<twirp>.freeze, ["~> 1.1".freeze])
  s.add_runtime_dependency(%q<google-protobuf>.freeze, [">= 3.14".freeze, "< 5.0".freeze])
  s.add_development_dependency(%q<bundler>.freeze, [">= 0".freeze])
  s.add_development_dependency(%q<rake>.freeze, [">= 0".freeze])
  s.add_development_dependency(%q<rspec>.freeze, [">= 0".freeze])
end
