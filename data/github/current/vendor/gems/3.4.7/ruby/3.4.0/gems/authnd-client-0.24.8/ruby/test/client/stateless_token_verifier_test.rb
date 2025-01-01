# frozen_string_literal: true

require_relative "../test_helper"
require_relative "./stateless_token_test_helpers"

require "securerandom"
require "timecop"

module Authnd
  module Client
    class StatelessTokenVerifierTest < Minitest::Test
      def setup
        exp = (Time.now.utc + 60).to_i # 1 minute from now
        iat = (Time.now.utc + 3600).to_i # 1 hour ago
        nbf = (Time.now.utc - 5).to_i # 5 seconds ago

        @claims = {
          "iss": "github/authnd",
          "exp": exp,
          "nbf": nbf,
          "iat": iat,
          "jti": SecureRandom.uuid,
          "actor.id": 2,
          "actor.type": "User",
          "user.login": "monalisa",
          "credential.id": 2,
          "credential.type": "PersonalAccessToken",
          "token.hash": "WSG7PuvFqRrmK2lrP96dVBqHM30JPLuzgnTDXbkFAPs=",
          "token.suffix": "6KXzMwbw",

        }

        @attributes = {
          "actor.id" => 2,
          "actor.type" => "User",
          "credential.id" => 2,
          "user.login" => "monalisa",
          "credential.scopes" => [],
          "organization.sso_authorized_ids" => [],
          "credential.type" => "PersonalAccessToken",
          "token.hash" => "WSG7PuvFqRrmK2lrP96dVBqHM30JPLuzgnTDXbkFAPs=",
          "token.suffix" => "6KXzMwbw",
          "credential.created_at_utc" => Google::Protobuf::Timestamp.new(seconds: iat),
          "credential.issued_at_utc" => Google::Protobuf::Timestamp.new(seconds: iat),
          "credential.expires_at_utc" => Google::Protobuf::Timestamp.new(seconds: exp),
        }

        @private_key_one = generate_ecdsa_key
        @base64_public_key_one = get_base64_encoded_public_key(@private_key_one)
        @public_key_one_fingerprint = generate_ecdsa_fingerprint(@base64_public_key_one)
        @jwt_one = generate_jwt(@claims, @private_key_one, @public_key_one_fingerprint)

        @private_key_two = generate_ecdsa_key
        @base64_public_key_two = get_base64_encoded_public_key(@private_key_two)
        @public_key_two_fingerprint = generate_ecdsa_fingerprint(@base64_public_key_two)
        @jwt_two = generate_jwt(@claims, @private_key_two, @public_key_two_fingerprint)

        ENV["TOKEN_EXCHANGER_PUBLIC_KEYS"] = "#{@base64_public_key_one};#{@base64_public_key_two}"
        @token_verifier = Authnd::Client::StatelessTokenVerifier.new
      end

      def test_missing_kid
        jwt = generate_jwt(@claims, @private_key_one, nil)
        assert_raises JWT::DecodeError do
          @token_verifier.verify_token(jwt)
        end
      end

      def test_invalid_kid
        jwt = generate_jwt(@claims, @private_key_one, "invalid_kid")
        assert_raises JWT::DecodeError do
          @token_verifier.verify_token(jwt)
        end
      end

      def test_first_key
        result = @token_verifier.verify_token(@jwt_one)
        assert_equal(:RESULT_SUCCESS, result.result)
        assert_equal(@attributes, result.attributes)
      end

      def test_second_key
        result = @token_verifier.verify_token(@jwt_two)
        assert_equal(:RESULT_SUCCESS, result.result)
        assert_equal(@attributes, result.attributes)
      end

      def test_unregistered_key
        unreg_private_key = generate_ecdsa_key
        unreg_public_key = get_base64_encoded_public_key(unreg_private_key)
        unreg_public_key_fingerprint = generate_ecdsa_fingerprint(unreg_public_key)
        bad_jwt = generate_jwt(@claims, unreg_private_key, unreg_public_key_fingerprint)

        assert_raises JWT::DecodeError do
          @token_verifier.verify_token(bad_jwt)
        end
      end

      def test_validates_exp
        assert_raises JWT::DecodeError do
          Timecop.freeze(Time.now.utc + 300) do # 5 minutes from now
            @token_verifier.verify_token(@jwt_one)
          end
        end
      end

      def test_validates_nbf
        assert_raises JWT::DecodeError do
          Timecop.freeze(Time.now.utc - 300) do # 5 minutes ago
            @token_verifier.verify_token(@jwt_one)
          end
        end
      end

      def test_validates_iss
        claims = @claims.clone.merge("iss": "hackers-r-us")
        bad_jwt = generate_jwt(claims, @private_key_one, @public_key_one_fingerprint)
        assert_raises JWT::DecodeError do
          @token_verifier.verify_token(bad_jwt)
        end
      end

      def test_oauth_app_token
        claims = @claims.clone.merge(
          "credential.type": "OAuthApplicationToken",
          "credential.scopes": %w[repo user],
          "organization.sso_authorized_ids": [1, 2, 3],
        )
        jwt = generate_jwt(claims, @private_key_one, @public_key_one_fingerprint)

        result = @token_verifier.verify_token(jwt)
        assert_equal(:RESULT_SUCCESS, result.result)
        assert_equal("OAuthApplicationToken", result.attributes["credential.type"])
        assert_equal(%w[repo user], result.attributes["credential.scopes"])
        assert_equal([1, 2, 3], result.attributes["organization.sso_authorized_ids"])
      end
    end
  end
end
