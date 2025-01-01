# -*- encoding: utf-8 -*-
# stub: hosted-compute-ims 0.0.1 ruby .

Gem::Specification.new do |s|
  s.name = "hosted-compute-ims".freeze
  s.version = "0.0.1".freeze

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.require_paths = [".".freeze]
  s.authors = ["@github/compute-flex".freeze]
  s.date = "2025-08-21"
  s.files = ["buf/validate/validate_pb.rb".freeze, "hosted-compute-ims.rb".freeze, "services/admin_api/admin_service_pb.rb".freeze, "services/admin_api/admin_service_twirp.rb".freeze, "services/images_api/images_service_pb.rb".freeze, "services/images_api/images_service_twirp.rb".freeze, "services/internal_api/internal_service_pb.rb".freeze, "services/internal_api/internal_service_twirp.rb".freeze, "shared/actor_pb.rb".freeze, "shared/actor_twirp.rb".freeze, "shared/enums_pb.rb".freeze, "shared/enums_twirp.rb".freeze]
  s.homepage = "https://github.com/github/hosted-compute-ims".freeze
  s.rubygems_version = "3.5.22".freeze
  s.summary = "Ruby client for Hosted Compute Image Management service".freeze

  s.installed_by_version = "3.5.22".freeze

  s.specification_version = 4

  s.add_runtime_dependency(%q<twirp>.freeze, ["~> 1.1".freeze])
end
