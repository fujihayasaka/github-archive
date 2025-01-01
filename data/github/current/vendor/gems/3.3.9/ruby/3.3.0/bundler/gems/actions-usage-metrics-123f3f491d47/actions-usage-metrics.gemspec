# -*- encoding: utf-8 -*-
# stub: actions-usage-metrics 1.0.36 ruby ruby/lib

Gem::Specification.new do |s|
  s.name = "actions-usage-metrics".freeze
  s.version = "1.0.36".freeze

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.require_paths = ["ruby/lib".freeze]
  s.authors = ["#actions-fusion".freeze]
  s.date = "2025-08-21"
  s.files = ["proto/usage.proto".freeze, "ruby/lib/actions-usage-metrics.rb".freeze, "ruby/lib/client/client.rb".freeze, "ruby/lib/client/request_signing_middleware.rb".freeze, "ruby/lib/client/version.rb".freeze, "ruby/lib/proto/export_api_pb.rb".freeze, "ruby/lib/proto/export_api_twirp.rb".freeze, "ruby/lib/proto/kafka_message_pb.rb".freeze, "ruby/lib/proto/kafka_message_twirp.rb".freeze, "ruby/lib/proto/sign_api_pb.rb".freeze, "ruby/lib/proto/sign_api_twirp.rb".freeze, "ruby/lib/proto/usage_pb.rb".freeze, "ruby/lib/proto/usage_twirp.rb".freeze]
  s.homepage = "https://github.com/github/actions-usage-metrics".freeze
  s.rubygems_version = "3.5.22".freeze
  s.summary = "Ruby client for actions-usage-metrics".freeze

  s.installed_by_version = "3.5.22".freeze

  s.specification_version = 4

  s.add_runtime_dependency(%q<faraday>.freeze, [">= 0.17".freeze, "< 3".freeze])
  s.add_runtime_dependency(%q<twirp>.freeze, ["~> 1.10".freeze])
  s.add_development_dependency(%q<google-protobuf>.freeze, ["~> 3.21".freeze])
  s.add_development_dependency(%q<rack>.freeze, ["~> 3.0".freeze])
end
