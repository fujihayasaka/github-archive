# -*- encoding: utf-8 -*-
# stub: authnd-client 0.23.1 ruby ruby/lib

Gem::Specification.new do |s|
  s.name = "authnd-client".freeze
  s.version = "0.23.1".freeze

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.require_paths = ["ruby/lib".freeze]
  s.authors = ["davecheney".freeze, "fatih".freeze, "sbryant".freeze, "dbussink".freeze, "shawnfeldman".freeze, "anurse".freeze, "jphenow".freeze]
  s.date = "1980-01-02"
  s.files = ["proto/authentication/v0/attributes.proto".freeze, "proto/authentication/v0/authenticate.proto".freeze, "proto/authentication/v0/authentication_api.proto".freeze, "proto/authentication/v0/credentials.proto".freeze, "proto/authentication/v0/find.proto".freeze, "proto/authentication/v0/issue.proto".freeze, "proto/authentication/v0/mobile_device_auth.proto".freeze, "proto/authentication/v0/mobile_device_keys.proto".freeze, "proto/authentication/v0/revoke.proto".freeze, "proto/authentication/v0/verify.proto".freeze, "ruby/lib/authnd-client.rb".freeze, "ruby/lib/authnd-client/attribute_extensions.rb".freeze, "ruby/lib/authnd-client/client/authenticator.rb".freeze, "ruby/lib/authnd-client/client/constants.rb".freeze, "ruby/lib/authnd-client/client/credential_manager.rb".freeze, "ruby/lib/authnd-client/client/credential_validator.rb".freeze, "ruby/lib/authnd-client/client/decoratable.rb".freeze, "ruby/lib/authnd-client/client/faraday_middleware/hmac_auth.rb".freeze, "ruby/lib/authnd-client/client/faraday_middleware/tenant_context.rb".freeze, "ruby/lib/authnd-client/client/headers.rb".freeze, "ruby/lib/authnd-client/client/identity_manager.rb".freeze, "ruby/lib/authnd-client/client/middleware/base.rb".freeze, "ruby/lib/authnd-client/client/middleware/instrumenters/noop.rb".freeze, "ruby/lib/authnd-client/client/middleware/retry.rb".freeze, "ruby/lib/authnd-client/client/middleware/timing.rb".freeze, "ruby/lib/authnd-client/client/mobile_device_manager.rb".freeze, "ruby/lib/authnd-client/client/service_client_base.rb".freeze, "ruby/lib/authnd-client/client/stateless_token_verifier.rb".freeze, "ruby/lib/authnd-client/client/token.rb".freeze, "ruby/lib/authnd-client/client/token_exchanger.rb".freeze, "ruby/lib/authnd-client/credentials_extensions.rb".freeze, "ruby/lib/authnd-client/errors.rb".freeze, "ruby/lib/authnd-client/proto/authentication/v0/attributes_pb.rb".freeze, "ruby/lib/authnd-client/proto/authentication/v0/authenticate_pb.rb".freeze, "ruby/lib/authnd-client/proto/authentication/v0/authentication_api_pb.rb".freeze, "ruby/lib/authnd-client/proto/authentication/v0/authentication_api_twirp.rb".freeze, "ruby/lib/authnd-client/proto/authentication/v0/credentials_pb.rb".freeze, "ruby/lib/authnd-client/proto/authentication/v0/find_pb.rb".freeze, "ruby/lib/authnd-client/proto/authentication/v0/issue_pb.rb".freeze, "ruby/lib/authnd-client/proto/authentication/v0/mobile_device_auth_pb.rb".freeze, "ruby/lib/authnd-client/proto/authentication/v0/mobile_device_keys_pb.rb".freeze, "ruby/lib/authnd-client/proto/authentication/v0/revoke_pb.rb".freeze, "ruby/lib/authnd-client/proto/authentication/v0/verify_pb.rb".freeze, "ruby/lib/authnd-client/response.rb".freeze, "ruby/lib/authnd-client/response_extensions.rb".freeze, "ruby/lib/authnd-client/version.rb".freeze, "ruby/test/attribute_extensions_test.rb".freeze, "ruby/test/authnd_server_helper.rb".freeze, "ruby/test/client/authenticator_integration_test.rb".freeze, "ruby/test/client/authenticator_test.rb".freeze, "ruby/test/client/credential_manager_integration_test.rb".freeze, "ruby/test/client/credential_manager_test.rb".freeze, "ruby/test/client/credential_validator_test.rb".freeze, "ruby/test/client/headers_test.rb".freeze, "ruby/test/client/middleware/base_test.rb".freeze, "ruby/test/client/middleware/instrumenters/noop_test.rb".freeze, "ruby/test/client/middleware/middleware_test.rb".freeze, "ruby/test/client/middleware/retry_test.rb".freeze, "ruby/test/client/mobile_device_manager_integration_test.rb".freeze, "ruby/test/client/mobile_device_manager_test.rb".freeze, "ruby/test/client/service_client_test_helpers.rb".freeze, "ruby/test/client/stateless_token_test_helpers.rb".freeze, "ruby/test/client/stateless_token_verifier_test.rb".freeze, "ruby/test/client/token_test.rb".freeze, "ruby/test/credential_extensions_test.rb".freeze, "ruby/test/response_test.rb".freeze, "ruby/test/test_helper.rb".freeze]
  s.homepage = "https://github.com/github/authnd".freeze
  s.licenses = ["Nonstandard".freeze]
  s.rubygems_version = "3.6.9".freeze
  s.summary = "Ruby client for authnd services".freeze

  s.installed_by_version = "3.6.9".freeze

  s.specification_version = 4

  s.add_runtime_dependency(%q<twirp>.freeze, ["~> 1.1".freeze])
  s.add_runtime_dependency(%q<resilient>.freeze, ["~> 0.4".freeze])
  s.add_runtime_dependency(%q<faraday>.freeze, [">= 0".freeze])
end
