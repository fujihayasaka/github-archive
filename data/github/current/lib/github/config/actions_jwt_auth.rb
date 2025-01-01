# typed: true
# frozen_string_literal: true

module GitHub
  module Config
    module ActionsJWTAuth
      # The private key PEM that will sign JWTs. This is the actual secret loaded from vault.
      attr_accessor :actions_jwt_signing_key_pem

      # This signing key used to sign Actions JWTs
      def actions_jwt_signing_key
        @actions_jwt_signing_key ||= begin
          rsa_key = OpenSSL::PKey::RSA.new(actions_jwt_signing_key_pem)
          {
            key: rsa_key,
            kid: generate_kid(rsa_key.public_key),
          }
        end
      end

      # The keys that will be used to verify JWTs
      # This is an array of public keys which allows for key rotation
      # So that we could validate with multiple signing keys
      def actions_jwt_verification_keys
        [
          {
            key: actions_jwt_signing_key[:key].public_key,
            kid: actions_jwt_signing_key[:kid],
          }
        ]
      end

      private

      # Generate the Key ID (kid) for the given public key
      # This ensures we lookup the correct signing key when verifying the JWT
      def generate_kid(public_key)
        modulus = public_key.n.to_s(2)
        exponent = public_key.e.to_s(2)

        key_data = modulus + exponent

        # Generate the Key ID (kid) using SHA-256 and Base64 URL encoding
        Base64.urlsafe_encode64(Digest::SHA256.digest(key_data)).gsub("=", "")
      end
    end
  end

  extend Config::ActionsJWTAuth
end
