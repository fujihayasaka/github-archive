# frozen_string_literal: true

require_relative "./service_client_base"

require "base64"
require "digest"
require "jwt"
require "openssl"

module Authnd
  module Client
    class StatelessTokenVerifier
      # Load the base64-encoded public keys from the environment,
      #  decode them, and store them in a hash with the fingerprint as the key
      def initialize(secret: ENV["TOKEN_EXCHANGER_PUBLIC_KEYS"])
        @public_keys = {}
        begin
          public_keys_env = secret.split(";")

          raise "No Token Exchanger public keys found" if public_keys_env.empty?

          public_keys_env.each do |key|
            # base64 decode the key and generate a SHA256 fingerprint
            decoded = Base64.strict_decode64(key)
            hash = Digest::SHA256.digest(decoded)
            fingerprint = Base64.strict_encode64(hash)

            # The authnd Go code omits base64 padding by using base64.RawStdEncoding
            # see https://github.com/github/authnd/blob/8a1941c9ec2f0686c51af54660318d5d533ac63e/client/token_verifier.go#L101-L111
            # None of the methods in Ruby's Base64 module seem to do this, so we have to do it manually.
            fingerprint = fingerprint.sub(/={0,2}$/, "") # remove trailing padding

            # create an EC key object and store it in the hash
            @public_keys[fingerprint] = OpenSSL::PKey::EC.new(decoded)
          end
        rescue StandardError
          raise "Unable to decode Token Exchanger public keys"
        end
      end

      # Verify the token and return the claims
      def verify_token(token)
        options = {
          algorithm: "ES256",
          iss: "github/authnd",
          verify_iss: true,
        }
        payload, = JWT.decode(token, nil, true, options) do |headers|
          kid = headers["kid"]
          raise JWT::VerificationError if kid.nil? || @public_keys[kid].nil?

          @public_keys[kid]
        end

        created_at_utc = payload[Attributes::CREDENTIAL_CREATED_AT] || payload["iat"]
        expires_at_utc = payload[Attributes::CREDENTIAL_EXPIRES_AT]
        credential_scopes = nil
        sso_authorized_ids = nil
        credential_type = payload[Attributes::CREDENTIAL_TYPE]

        if oauth_access?(credential_type)
          credential_scopes = payload[Attributes::CREDENTIAL_SCOPES] || []
          sso_authorized_ids = payload[Attributes::ORGANIZATION_SSO_AUTHORIZED_IDS] || []
        end

        # transfer attributes directly from the payload where possible
        attributes = payload.slice(
          Attributes::ACTOR_ID,
          Attributes::ACTOR_TYPE,
          Attributes::CREDENTIAL_ID,
          Attributes::USER_LOGIN,
          Attributes::PROGRAMMATIC_ACCESS_ID,
          Attributes::TOKEN_HASH,
          Attributes::TOKEN_SUFFIX,
          Attributes::APPLICATION_ID,
          Attributes::APPLICATION_TYPE,
          Attributes::APPLICATION_CLIENT_ID,
          Attributes::APPLICATION_OWNER_ID,
          Attributes::APPLICATION_OWNER_TYPE,
          Attributes::INSTALLATION_ID,
          Attributes::INSTALLATION_TARGET_ID,
          Attributes::INSTALLATION_TARGET_TYPE,
          Attributes::SCOPED_INSTALLATION_TYPE,
          Attributes::SCOPED_INSTALLATION_ID,
        )
        # add other attributes which come from standard JWT claims or otherwise need special handling
        attributes.merge!(
          {
            Attributes::CREDENTIAL_SCOPES => credential_scopes,
            Attributes::ORGANIZATION_SSO_AUTHORIZED_IDS => sso_authorized_ids,
            Attributes::CREDENTIAL_TYPE => credential_type,
            Attributes::CREDENTIAL_CREATED_AT => Google::Protobuf::Timestamp.new(seconds: created_at_utc),
            Attributes::CREDENTIAL_ISSUED_AT => Google::Protobuf::Timestamp.new(seconds: payload["iat"]),
          },
        )
        attributes[Attributes::CREDENTIAL_EXPIRES_AT] = Google::Protobuf::Timestamp.new(seconds: expires_at_utc) if expires_at_utc

        Authnd::Response.new(:RESULT_SUCCESS, attributes.compact)
      end

      private

      def oauth_access?(credential_type)
        case credential_type
        when "PersonalAccessToken", "OAuthApplicationToken", "UserToServerToken"
          true
        else
          false
        end
      end
    end
  end
end
