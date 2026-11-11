# -*- encoding: utf-8 -*-
# stub: github-proto-repositories 1.2.11 ruby lib

Gem::Specification.new do |s|
  s.name = "github-proto-repositories".freeze
  s.version = "1.2.11".freeze

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.require_paths = ["lib".freeze]
  s.authors = ["GitHub".freeze]
  s.date = "2026-01-14"
  s.files = ["lib/github-proto-repositories.rb".freeze, "lib/github/proto/repositories/v1/commits_api_pb.rb".freeze, "lib/github/proto/repositories/v1/commits_api_twirp.rb".freeze, "lib/github/proto/repositories/v1/issue_list_item_pb.rb".freeze, "lib/github/proto/repositories/v1/issue_list_item_twirp.rb".freeze, "lib/github/proto/repositories/v1/issues_api_pb.rb".freeze, "lib/github/proto/repositories/v1/issues_api_twirp.rb".freeze, "lib/github/proto/repositories/v1/repositories_api_pb.rb".freeze, "lib/github/proto/repositories/v1/repositories_api_twirp.rb".freeze, "lib/github/proto/repositories/v1/repository_list_item_pb.rb".freeze, "lib/github/proto/repositories/v1/repository_list_item_twirp.rb".freeze, "lib/github/proto/repositories/v1/repository_permission_list_item_pb.rb".freeze, "lib/github/proto/repositories/v1/repository_permission_list_item_twirp.rb".freeze, "lib/github/proto/repositories/v1/status_pb.rb".freeze, "lib/github/proto/repositories/v1/status_twirp.rb".freeze, "lib/github/proto/repositories/v1/user_permission_pb.rb".freeze, "lib/github/proto/repositories/v1/user_permission_twirp.rb".freeze, "lib/github/proto/repositories/v1/visibility_pb.rb".freeze, "lib/github/proto/repositories/v1/visibility_twirp.rb".freeze, "lib/github/proto/repositories/version.rb".freeze]
  s.homepage = "https://github.com/github/github-proto/tree/master/gen/ruby/repositories".freeze
  s.licenses = ["Nonstandard".freeze]
  s.rubygems_version = "3.5.22".freeze
  s.summary = "Generated client/server code for github/github repositories data.".freeze

  s.installed_by_version = "3.5.22".freeze

  s.specification_version = 4

  s.add_runtime_dependency(%q<twirp>.freeze, ["~> 1.1".freeze])
  s.add_development_dependency(%q<bundler>.freeze, [">= 0".freeze])
  s.add_development_dependency(%q<minitest>.freeze, ["~> 5.0".freeze])
  s.add_development_dependency(%q<rake>.freeze, [">= 0".freeze])
end
