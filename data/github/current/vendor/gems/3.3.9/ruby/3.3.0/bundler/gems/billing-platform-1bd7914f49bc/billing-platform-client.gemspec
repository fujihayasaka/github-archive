# -*- encoding: utf-8 -*-
# stub: billing-platform-client 0.51.0 ruby ruby/lib

Gem::Specification.new do |s|
  s.name = "billing-platform-client".freeze
  s.version = "0.51.0".freeze

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.require_paths = ["ruby/lib".freeze]
  s.authors = ["#billing-engineering".freeze]
  s.date = "2025-08-21"
  s.files = ["proto/admin-api.proto".freeze, "proto/base.proto".freeze, "proto/cost-center-api.proto".freeze, "proto/customer-api.proto".freeze, "proto/invoice-api.proto".freeze, "proto/pricing-api.proto".freeze, "proto/product-api.proto".freeze, "proto/subscriptions-api.proto".freeze, "proto/usage-api.proto".freeze, "proto/usage-report-api.proto".freeze, "ruby/lib/billing-platform.rb".freeze, "ruby/lib/billing-platform/api.rb".freeze, "ruby/lib/billing-platform/client.rb".freeze, "ruby/lib/billing-platform/twirp/hmac/request_signing_middleware.rb".freeze, "ruby/lib/billing-platform/version.rb".freeze, "ruby/lib/proto/admin-api_pb.rb".freeze, "ruby/lib/proto/admin-api_twirp.rb".freeze, "ruby/lib/proto/base_pb.rb".freeze, "ruby/lib/proto/base_twirp.rb".freeze, "ruby/lib/proto/cost-center-api_pb.rb".freeze, "ruby/lib/proto/cost-center-api_twirp.rb".freeze, "ruby/lib/proto/customer-api_pb.rb".freeze, "ruby/lib/proto/customer-api_twirp.rb".freeze, "ruby/lib/proto/invoice-api_pb.rb".freeze, "ruby/lib/proto/invoice-api_twirp.rb".freeze, "ruby/lib/proto/pricing-api_pb.rb".freeze, "ruby/lib/proto/pricing-api_twirp.rb".freeze, "ruby/lib/proto/product-api_pb.rb".freeze, "ruby/lib/proto/product-api_twirp.rb".freeze, "ruby/lib/proto/subscription-api_pb.rb".freeze, "ruby/lib/proto/subscription-api_twirp.rb".freeze, "ruby/lib/proto/subscriptions-api_pb.rb".freeze, "ruby/lib/proto/subscriptions-api_twirp.rb".freeze, "ruby/lib/proto/usage-api_pb.rb".freeze, "ruby/lib/proto/usage-api_twirp.rb".freeze, "ruby/lib/proto/usage-report-api_pb.rb".freeze, "ruby/lib/proto/usage-report-api_twirp.rb".freeze, "ruby/spec/billing-platform/client/admin_api_spec.rb".freeze, "ruby/spec/billing-platform/client/cost_center_api_spec.rb".freeze, "ruby/spec/billing-platform/client/customer_api_spec.rb".freeze, "ruby/spec/billing-platform/client/invoice_api_spec.rb".freeze, "ruby/spec/billing-platform/client/pricing_api_spec.rb".freeze, "ruby/spec/billing-platform/client/product_api_spec.rb".freeze, "ruby/spec/billing-platform/client/subscriptions_api_spec.rb".freeze, "ruby/spec/billing-platform/client/usage_api_spec.rb".freeze, "ruby/spec/billing-platform/client/usage_report_api_spec.rb".freeze, "ruby/spec/spec_helper.rb".freeze, "ruby/spec/support/twirp_test_helpers.rb".freeze]
  s.homepage = "https://github.com/github/billing-platform".freeze
  s.rubygems_version = "3.5.22".freeze
  s.summary = "Ruby client for the billing-platform API".freeze

  s.installed_by_version = "3.5.22".freeze

  s.specification_version = 4

  s.add_runtime_dependency(%q<faraday>.freeze, [">= 0.17".freeze, "< 3".freeze])
  s.add_runtime_dependency(%q<twirp>.freeze, ["~> 1.10".freeze])
  s.add_development_dependency(%q<google-protobuf>.freeze, ["~> 3.21".freeze])
  s.add_development_dependency(%q<rspec>.freeze, ["~> 3.12".freeze])
  s.add_development_dependency(%q<rack>.freeze, ["~> 2.2".freeze])
  s.add_development_dependency(%q<webmock>.freeze, ["~> 3.18".freeze])
  s.add_development_dependency(%q<simplecov>.freeze, ["~> 0.21.0".freeze])
end
