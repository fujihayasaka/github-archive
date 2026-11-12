# frozen_string_literal: true

require_relative "../test_helper"

module Authnd
  module Client
    class CredentialManagerTest < Minitest::Test
      include ServiceClientTestHelpers

      def test_initialize_with_string
        ex = assert_raises ArgumentError do
          Authnd::Client::CredentialManager.new("not_a_faraday_connection", catalog_service: TEST_CATALOG_SERVICE)
        end
        assert_equal "connection is not a Faraday::Connection", ex.message
      end

      def test_issue_token_forwards_request_to_twirp
        credential_manager = Authnd::Client::CredentialManager.new(test_connection, catalog_service: TEST_CATALOG_SERVICE)
        expected_req = Authnd::Proto::IssueTokenRequest.new(
          type: "test-token-type",
          attributes: [Authnd::Proto::Attribute.new(id: "actor.id", value: Authnd::Proto::Value.wrap("test-actor-id"))],
        )
        expected_resp = Twirp::ClientResp.new(data: Authnd::Proto::IssueTokenResponse.new(result: :RESULT_SUCCESS, token: "c0ffeecafe", token_id: 42), error: nil)
        stub_twirp_client credential_manager, :issue_token, expected_req, expected_resp

        actual_resp = credential_manager.issue_token("test-token-type", { "actor.id": "test-actor-id" })
        assert_predicate actual_resp, :success?
        assert_equal :RESULT_SUCCESS, actual_resp.result
        assert_equal "c0ffeecafe", actual_resp.token
        assert_equal 42, actual_resp.token_id
      end

      def test_issue_token_includes_expiry_time_if_provided
        time = Time.now

        credential_manager = Authnd::Client::CredentialManager.new(test_connection, catalog_service: TEST_CATALOG_SERVICE)
        expected_req = Authnd::Proto::IssueTokenRequest.new(
          type: "test-token-type",
          attributes: [Authnd::Proto::Attribute.new(id: "actor.id", value: Authnd::Proto::Value.wrap("test-actor-id"))],
          expires_at_time: Google::Protobuf::Timestamp.new(seconds: time.utc.tv_sec),
        )
        expected_resp = Twirp::ClientResp.new(data: Authnd::Proto::IssueTokenResponse.new(result: :RESULT_SUCCESS, token: "c0ffeecafe", token_id: 42), error: nil)
        stub_twirp_client credential_manager, :issue_token, expected_req, expected_resp

        actual_resp = credential_manager.issue_token("test-token-type", { "actor.id": "test-actor-id" }, expires_at: time)
        assert_predicate actual_resp, :success?
        assert_equal :RESULT_SUCCESS, actual_resp.result
        assert_equal "c0ffeecafe", actual_resp.token
        assert_equal 42, actual_resp.token_id
      end

      def test_issue_token_raises_on_twirp_error
        credential_manager = Authnd::Client::CredentialManager.new(test_connection, catalog_service: TEST_CATALOG_SERVICE)
        expected_req = Authnd::Proto::IssueTokenRequest.new(
          type: "test-token-type",
          attributes: [Authnd::Proto::Attribute.new(id: "actor.id", value: Authnd::Proto::Value.wrap("test-actor-id"))],
        )
        expected_twerr = Twirp::Error.internal("test twirp error")
        expected_resp = Twirp::ClientResp.new(data: nil, error: expected_twerr)
        stub_twirp_client credential_manager, :issue_token, expected_req, expected_resp

        ex = assert_raises Authnd::Proto::Error do
          credential_manager.issue_token("test-token-type", { "actor.id": "test-actor-id" })
        end
        assert_equal "internal: test twirp error", ex.message
        assert_equal expected_twerr, ex.twirp_error
      end

      def test_client_adds_request_hmac_to_request_when_providing_faraday_hmac_middleware
        hmac_key = "a-test-key"
        provided_hmac = nil

        test_connection = Faraday.new(url: UNREACHABLE_TWIRP_URL) do |f|
          f.use Authnd::Client::FaradayMiddleware::HMACAuth, hmac_key: hmac_key
          f.use Authnd::Client::FaradayMiddleware::TenantContext, tenant_id: 12_345
          f.adapter :test do |stub|
            stub.post("/twirp/github.authentication.v0.CredentialManager/IssueToken") do |env|
              provided_hmac = env.request_headers["Request-HMAC"]

              [500, {}, "test"]
            end
          end
        end

        service = Authnd::Client::CredentialManager.new(test_connection, catalog_service: TEST_CATALOG_SERVICE)

        assert_raises Authnd::Proto::Error do
          service.issue_token("test-token-type", { "actor.id": "test-actor-id" })
        end

        refute_nil provided_hmac

        timestamp, hmac = provided_hmac.split(".")
        digest = OpenSSL::Digest.new("SHA256")
        expected_hmac = OpenSSL::HMAC.new(hmac_key, digest)
        expected_hmac << timestamp
        assert_equal expected_hmac.to_s, hmac
      end

      def test_issue_token_uses_provided_connection
        provided_req = nil
        provided_catalog_service = nil
        provided_user_agent = nil
        expected_resp = Authnd::Proto::IssueTokenResponse.new(result: :RESULT_SUCCESS, token: "c0ffeecafe", token_id: 42)
        conn = Faraday.new(url: UNREACHABLE_TWIRP_URL) do |f|
          f.adapter :test do |stub|
            stub.post("/twirp/github.authentication.v0.CredentialManager/IssueToken") do |env|
              provided_req = Authnd::Proto::IssueTokenRequest.decode(env.body)
              provided_catalog_service = env.request_headers["Catalog-Service"]
              provided_user_agent = env.request_headers["User-Agent"]
              [
                200,
                { "Content-Type" => "application/protobuf" },
                Authnd::Proto::IssueTokenResponse.encode(expected_resp),
              ]
            end
          end
        end
        service = Authnd::Client::CredentialManager.new(conn, catalog_service: TEST_CATALOG_SERVICE)
        resp = service.issue_token("test-token-type", { "actor.id": "test-actor-id" })

        assert_predicate resp, :success?
        assert_equal :RESULT_SUCCESS, resp.result
        assert_equal "c0ffeecafe", resp.token
        assert_equal 42, resp.token_id

        refute_nil provided_req
        assert_equal "test-token-type", provided_req.type
        assert_equal [Authnd::Proto::Attribute.new(id: "actor.id", value: Authnd::Proto::Value.wrap("test-actor-id"))], provided_req.attributes

        assert_equal TEST_CATALOG_SERVICE, provided_catalog_service
        assert_equal "authnd-ruby/#{Authnd::VERSION}", provided_user_agent
      end

      def test_verify_credentails_validates_candidates
        credential_manager = Authnd::Client::CredentialManager.new(test_connection, catalog_service: TEST_CATALOG_SERVICE)
        assert_raises ArgumentError do
          credential_manager.verify_credentials("") # not an array
          credential_manager.verify_credentials([""])
        end
      end

      def test_issue_stateless_app_token_forwards_request_to_twirp
        credential_manager = Authnd::Client::CredentialManager.new(test_connection, catalog_service: TEST_CATALOG_SERVICE)

        azc = Authnd::Proto::AuthorizationContext.new(
          installation: Authnd::Proto::AuthorizationContext::Installation.new(id: 9012),
        )
        expected_req = Authnd::Proto::IssueStatelessAppTokenRequest.new(
          token_type: :TOKEN_TYPE_S2S,
          attributes: [Authnd::Proto::Attribute.new(id: "application.id", value: Authnd::Proto::Value.wrap(1234))],
          authorization_contexts: Authnd::Proto::AuthorizationContexts.new(contexts: [azc]),
        )
        expected_resp = Twirp::ClientResp.new(
          data: Authnd::Proto::IssueStatelessAppTokenResponse.new(result: :RESULT_SUCCESS, token: "jwt-token-string"),
          error: nil,
        )
        stub_twirp_client credential_manager, :issue_stateless_app_token, expected_req, expected_resp

        actual_resp = credential_manager.issue_stateless_app_token(
          :TOKEN_TYPE_S2S,
          { "application.id": 1234 },
          authorization_context: azc,
        )
        assert_equal :RESULT_SUCCESS, actual_resp.result
        assert_equal "jwt-token-string", actual_resp.token
      end

      def test_issue_stateless_app_token_exposes_credential_id_from_response
        credential_manager = Authnd::Client::CredentialManager.new(test_connection, catalog_service: TEST_CATALOG_SERVICE)

        azc = Authnd::Proto::AuthorizationContext.new(
          installation: Authnd::Proto::AuthorizationContext::Installation.new(id: 9012),
        )
        expected_req = Authnd::Proto::IssueStatelessAppTokenRequest.new(
          token_type: :TOKEN_TYPE_S2S,
          attributes: [Authnd::Proto::Attribute.new(id: "application.id", value: Authnd::Proto::Value.wrap(1234))],
          authorization_contexts: Authnd::Proto::AuthorizationContexts.new(contexts: [azc]),
        )
        expected_resp = Twirp::ClientResp.new(
          data: Authnd::Proto::IssueStatelessAppTokenResponse.new(
            result: :RESULT_SUCCESS,
            token: "jwt-token-string",
            token_id: "jti-abc123",
            credential_id: 1_234_567_890,
          ),
          error: nil,
        )
        stub_twirp_client credential_manager, :issue_stateless_app_token, expected_req, expected_resp

        actual_resp = credential_manager.issue_stateless_app_token(
          :TOKEN_TYPE_S2S,
          { "application.id": 1234 },
          authorization_context: azc,
        )
        assert_equal "jti-abc123", actual_resp.token_id
        assert_equal 1_234_567_890, actual_resp.credential_id
      end

      def test_issue_stateless_app_token_with_integer_token_type
        credential_manager = Authnd::Client::CredentialManager.new(test_connection, catalog_service: TEST_CATALOG_SERVICE)

        azc = Authnd::Proto::AuthorizationContext.new(
          oauth: Authnd::Proto::AuthorizationContext::OAuth.new(id: 100),
        )
        expected_req = Authnd::Proto::IssueStatelessAppTokenRequest.new(
          token_type: :TOKEN_TYPE_U2S,
          attributes: [Authnd::Proto::Attribute.new(id: "application.id", value: Authnd::Proto::Value.wrap(1234))],
          authorization_contexts: Authnd::Proto::AuthorizationContexts.new(contexts: [azc]),
        )
        expected_resp = Twirp::ClientResp.new(
          data: Authnd::Proto::IssueStatelessAppTokenResponse.new(result: :RESULT_SUCCESS, token: "u2s-token"),
          error: nil,
        )
        stub_twirp_client credential_manager, :issue_stateless_app_token, expected_req, expected_resp

        actual_resp = credential_manager.issue_stateless_app_token(
          2,
          { "application.id": 1234 },
          authorization_context: azc,
        )
        assert_equal :RESULT_SUCCESS, actual_resp.result
        assert_equal "u2s-token", actual_resp.token
      end

      def test_issue_stateless_app_token_includes_expiry_time_if_provided
        time = Time.now

        credential_manager = Authnd::Client::CredentialManager.new(test_connection, catalog_service: TEST_CATALOG_SERVICE)

        azc = Authnd::Proto::AuthorizationContext.new(
          scoped_installation: Authnd::Proto::AuthorizationContext::ScopedInstallation.new(id: 42),
        )
        expected_req = Authnd::Proto::IssueStatelessAppTokenRequest.new(
          token_type: :TOKEN_TYPE_S2S,
          attributes: [Authnd::Proto::Attribute.new(id: "application.id", value: Authnd::Proto::Value.wrap(1234))],
          authorization_contexts: Authnd::Proto::AuthorizationContexts.new(contexts: [azc]),
          expires_at_time: Google::Protobuf::Timestamp.new(seconds: time.utc.tv_sec),
        )
        expected_resp = Twirp::ClientResp.new(
          data: Authnd::Proto::IssueStatelessAppTokenResponse.new(result: :RESULT_SUCCESS, token: "jwt-with-expiry"),
          error: nil,
        )
        stub_twirp_client credential_manager, :issue_stateless_app_token, expected_req, expected_resp

        actual_resp = credential_manager.issue_stateless_app_token(
          :TOKEN_TYPE_S2S,
          { "application.id": 1234 },
          authorization_context: azc,
          expires_at: time,
        )
        assert_equal :RESULT_SUCCESS, actual_resp.result
        assert_equal "jwt-with-expiry", actual_resp.token
      end

      def test_issue_stateless_app_token_raises_on_twirp_error
        credential_manager = Authnd::Client::CredentialManager.new(test_connection, catalog_service: TEST_CATALOG_SERVICE)

        azc = Authnd::Proto::AuthorizationContext.new(
          installation: Authnd::Proto::AuthorizationContext::Installation.new(id: 9012),
        )
        expected_req = Authnd::Proto::IssueStatelessAppTokenRequest.new(
          token_type: :TOKEN_TYPE_S2S,
          attributes: [Authnd::Proto::Attribute.new(id: "application.id", value: Authnd::Proto::Value.wrap(1234))],
          authorization_contexts: Authnd::Proto::AuthorizationContexts.new(contexts: [azc]),
        )
        expected_twerr = Twirp::Error.internal("test twirp error")
        expected_resp = Twirp::ClientResp.new(data: nil, error: expected_twerr)
        stub_twirp_client credential_manager, :issue_stateless_app_token, expected_req, expected_resp

        ex = assert_raises Authnd::Proto::Error do
          credential_manager.issue_stateless_app_token(
            :TOKEN_TYPE_S2S,
            { "application.id": 1234 },
            authorization_context: azc,
          )
        end
        assert_equal "internal: test twirp error", ex.message
        assert_equal expected_twerr, ex.twirp_error
      end

      def test_issue_stateless_app_token_raises_on_invalid_token_type_symbol
        credential_manager = Authnd::Client::CredentialManager.new(test_connection, catalog_service: TEST_CATALOG_SERVICE)
        azc = Authnd::Proto::AuthorizationContext.new(
          installation: Authnd::Proto::AuthorizationContext::Installation.new(id: 1),
        )

        ex = assert_raises ArgumentError do
          credential_manager.issue_stateless_app_token(
            :INVALID_TYPE,
            { "application.id": 1234 },
            authorization_context: azc,
          )
        end
        assert_match(/unknown TokenType symbol/, ex.message)
      end

      def test_issue_stateless_app_token_raises_on_invalid_token_type_class
        credential_manager = Authnd::Client::CredentialManager.new(test_connection, catalog_service: TEST_CATALOG_SERVICE)
        azc = Authnd::Proto::AuthorizationContext.new(
          installation: Authnd::Proto::AuthorizationContext::Installation.new(id: 1),
        )

        ex = assert_raises ArgumentError do
          credential_manager.issue_stateless_app_token(
            "s2s",
            { "application.id": 1234 },
            authorization_context: azc,
          )
        end
        assert_match(/token_type must be a Symbol or Integer/, ex.message)
      end

      def test_issue_stateless_app_token_raises_on_invalid_integer_token_type
        credential_manager = Authnd::Client::CredentialManager.new(test_connection, catalog_service: TEST_CATALOG_SERVICE)
        azc = Authnd::Proto::AuthorizationContext.new(
          installation: Authnd::Proto::AuthorizationContext::Installation.new(id: 1),
        )

        ex = assert_raises ArgumentError do
          credential_manager.issue_stateless_app_token(
            999, # invalid token type
            { "application.id": 1234 },
            authorization_context: azc,
          )
        end
        assert_match(/token_type must be a valid TokenType/, ex.message)
      end

      def test_issue_stateless_app_token_raises_on_invalid_attributes_type
        credential_manager = Authnd::Client::CredentialManager.new(test_connection, catalog_service: TEST_CATALOG_SERVICE)
        azc = Authnd::Proto::AuthorizationContext.new(
          installation: Authnd::Proto::AuthorizationContext::Installation.new(id: 1),
        )

        ex = assert_raises ArgumentError do
          credential_manager.issue_stateless_app_token(
            :TOKEN_TYPE_S2S,
            "not-a-hash",
            authorization_context: azc,
          )
        end
        assert_equal "attributes must be a Hash", ex.message
      end

      def test_issue_stateless_app_token_raises_on_invalid_application_id
        credential_manager = Authnd::Client::CredentialManager.new(test_connection, catalog_service: TEST_CATALOG_SERVICE)
        azc = Authnd::Proto::AuthorizationContext.new(
          installation: Authnd::Proto::AuthorizationContext::Installation.new(id: 1),
        )

        ex = assert_raises ArgumentError do
          credential_manager.issue_stateless_app_token(
            :TOKEN_TYPE_S2S,
            { "application.id": 0 },
            authorization_context: azc,
          )
        end
        assert_equal "application.id must be a positive Integer", ex.message
      end

      def test_issue_stateless_app_token_raises_on_invalid_authorization_context_type
        credential_manager = Authnd::Client::CredentialManager.new(test_connection, catalog_service: TEST_CATALOG_SERVICE)

        ex = assert_raises ArgumentError do
          credential_manager.issue_stateless_app_token(
            :TOKEN_TYPE_S2S,
            { "application.id": 1234 },
            authorization_context: "not-a-context",
          )
        end
        assert_equal "authorization_context must be an AuthorizationContext", ex.message
      end

      def test_issue_stateless_app_token_raises_on_authorization_context_with_no_kind
        credential_manager = Authnd::Client::CredentialManager.new(test_connection, catalog_service: TEST_CATALOG_SERVICE)
        azc = Authnd::Proto::AuthorizationContext.new

        ex = assert_raises ArgumentError do
          credential_manager.issue_stateless_app_token(
            :TOKEN_TYPE_S2S,
            { "application.id": 1234 },
            authorization_context: azc,
          )
        end
        assert_equal "authorization_context kind must be set", ex.message
      end

      def test_issue_stateless_app_token_raises_on_authorization_context_with_non_positive_id
        credential_manager = Authnd::Client::CredentialManager.new(test_connection, catalog_service: TEST_CATALOG_SERVICE)

        {
          oauth: Authnd::Proto::AuthorizationContext.new(oauth: Authnd::Proto::AuthorizationContext::OAuth.new(id: 0)),
          installation: Authnd::Proto::AuthorizationContext.new(installation: Authnd::Proto::AuthorizationContext::Installation.new(id: 0)),
          scoped_installation: Authnd::Proto::AuthorizationContext.new(scoped_installation: Authnd::Proto::AuthorizationContext::ScopedInstallation.new(id: 0)),
          site_scoped_installation: Authnd::Proto::AuthorizationContext.new(site_scoped_installation: Authnd::Proto::AuthorizationContext::SiteScopedInstallation.new(id: 0)),
        }.each_value do |azc|
          ex = assert_raises ArgumentError do
            credential_manager.issue_stateless_app_token(
              :TOKEN_TYPE_S2S,
              { "application.id": 1234 },
              authorization_context: azc,
            )
          end
          assert_equal "authorization_context id must be a positive Integer", ex.message
        end
      end

      def test_issue_stateless_app_token_raises_on_invalid_expires_at
        credential_manager = Authnd::Client::CredentialManager.new(test_connection, catalog_service: TEST_CATALOG_SERVICE)
        azc = Authnd::Proto::AuthorizationContext.new(
          installation: Authnd::Proto::AuthorizationContext::Installation.new(id: 1),
        )

        ex = assert_raises ArgumentError do
          credential_manager.issue_stateless_app_token(
            :TOKEN_TYPE_S2S,
            { "application.id": 1234 },
            authorization_context: azc,
            expires_at: "not-a-time",
          )
        end
        assert_equal "expires_at must be a Time", ex.message
      end
    end
  end
end
