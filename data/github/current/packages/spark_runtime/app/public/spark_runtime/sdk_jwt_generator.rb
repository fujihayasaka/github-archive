# typed: strict
# frozen_string_literal: true

module SparkRuntime
  class SdkJwtGenerator
    sig do
      params(
        auth_token: String,
        auth_token_expires_at: T.any(ActiveSupport::TimeWithZone, Time),
        app_name: String,
        app_owner_login: String,
        token_user: String,
        private_pem: String
      ).void
    end
    def initialize(auth_token, auth_token_expires_at, app_name, app_owner_login, token_user, private_pem)
      raise ArgumentError, "Missing private key configuration. Is WORKBENCH_ACA_JWT_PRIVATE_KEY set?" if private_pem.blank?

      @auth_token = auth_token
      @auth_token_expires_at = auth_token_expires_at
      @app_name = app_name
      @app_owner_login = app_owner_login
      @token_user = token_user
      @private_key = T.let(OpenSSL::PKey::EC.new(private_pem), OpenSSL::PKey::EC)
    end

    sig { returns(T::Hash[String, String]) }
    def plain_payload
      {
        "data" => {
          "tkn" => @auth_token,
          "app" => @app_name,
          "app_user" => @app_owner_login,
        },
        "aud" => "SparkSDK",
        "exp" => @auth_token_expires_at.to_i,
        "iss" => "GitHub",
        "sub" => @token_user,
      }
    end

    sig { returns(String) }
    def jwt
      JWT.encode(plain_payload, @private_key, "ES384")
    end
  end
end
