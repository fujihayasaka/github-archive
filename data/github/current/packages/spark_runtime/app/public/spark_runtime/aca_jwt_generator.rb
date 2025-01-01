# typed: strict
# frozen_string_literal: true

module SparkRuntime
  class AcaJwtGenerator
    sig do
      params(
        app: String,
        deploy_user: String,
        private_pem: String,
        at_hash: String,
        expires_at: T.any(ActiveSupport::TimeWithZone, Time),
      ).void
    end
    def initialize(app, deploy_user, private_pem, at_hash, expires_at)
      raise ArgumentError, "Missing private key configuration. Is WORKBENCH_ACA_JWT_PRIVATE_KEY set?" if private_pem.blank?

      @app = app
      @deploy_user = deploy_user
      @private_key = T.let(OpenSSL::PKey::EC.new(private_pem), OpenSSL::PKey::EC)
      @at_hash = at_hash
      @expires_at = expires_at
    end

    sig { returns(T::Hash[String, String]) }
    def plain_payload
      {
        "data" => {
          "app" => @app,
        },
        "aud" => "ACA",
        "exp" => @expires_at.to_i,
        "iss" => "GitHub",
        "sub" => @deploy_user,
        "at_hash" => @at_hash,
      }
    end

    sig { returns(String) }
    def jwt
      # if this algorithm changes, also change #token_at_hash in app/controllers/runtime/auth_controller.rb
      JWT.encode(plain_payload, @private_key, "ES384")
    end
  end
end
