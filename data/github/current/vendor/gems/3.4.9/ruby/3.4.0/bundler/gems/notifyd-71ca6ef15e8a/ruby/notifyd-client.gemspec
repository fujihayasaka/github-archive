# -*- encoding: utf-8 -*-
# stub: notifyd-client 1.9.1 ruby lib

Gem::Specification.new do |s|
  s.name = "notifyd-client".freeze
  s.version = "1.9.1".freeze

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.require_paths = ["lib".freeze]
  s.authors = ["@github/notifications".freeze]
  s.date = "1980-01-02"
  s.files = ["lib/notifyd-client.rb".freeze, "lib/notifyd.rb".freeze, "lib/notifyd/adapter_plug.rb".freeze, "lib/notifyd/builder.rb".freeze, "lib/notifyd/client.rb".freeze, "lib/notifyd/hmac_auth_middleware.rb".freeze, "lib/notifyd/hmac_auth_plug.rb".freeze, "lib/notifyd/plug.rb".freeze, "lib/notifyd/proto.rb".freeze, "lib/notifyd/proto/layouts/email/layouts_pb.rb".freeze, "lib/notifyd/proto/layouts/mobile/layouts_pb.rb".freeze, "lib/notifyd/proto/services/devicetokens/v2/service_pb.rb".freeze, "lib/notifyd/proto/services/devicetokens/v2/service_twirp.rb".freeze, "lib/notifyd/proto/services/maintenance/service_pb.rb".freeze, "lib/notifyd/proto/services/maintenance/service_twirp.rb".freeze, "lib/notifyd/proto/services/newsies/service_pb.rb".freeze, "lib/notifyd/proto/services/newsies/service_twirp.rb".freeze, "lib/notifyd/proto/services/routingsettings/service_pb.rb".freeze, "lib/notifyd/proto/services/routingsettings/service_twirp.rb".freeze, "lib/notifyd/proto/services/subscriptions/service_pb.rb".freeze, "lib/notifyd/proto/services/subscriptions/service_twirp.rb".freeze, "lib/notifyd/proto/services/test/service_pb.rb".freeze, "lib/notifyd/proto/services/test/service_twirp.rb".freeze, "lib/notifyd/retry_plug.rb".freeze, "lib/notifyd/rubocop_formatter.rb".freeze, "lib/notifyd/version.rb".freeze, "lib/tapioca/dsl/compilers/notifyd_client.rb".freeze, "lib/tapioca/dsl/compilers/notifyd_twirp_clients.rb".freeze, "rbi/annotations/notifyd.rbi".freeze, "rbi/notifyd/builder.rbi".freeze, "rbi/notifyd/client.rbi".freeze]
  s.homepage = "https://github.com/github/notifyd".freeze
  s.rubygems_version = "3.6.9".freeze
  s.summary = "Ruby client for notifyd services".freeze

  s.installed_by_version = "3.6.9".freeze

  s.specification_version = 4

  s.add_runtime_dependency(%q<google-protobuf>.freeze, ["~> 3.14".freeze])
  s.add_runtime_dependency(%q<twirp>.freeze, ["~> 1.10".freeze])
  s.add_runtime_dependency(%q<resilient>.freeze, ["~> 0.4.0".freeze])
  s.add_runtime_dependency(%q<faraday>.freeze, [">= 0.17".freeze, "< 2".freeze])
  s.add_runtime_dependency(%q<sorbet-runtime>.freeze, [">= 0".freeze])
end
