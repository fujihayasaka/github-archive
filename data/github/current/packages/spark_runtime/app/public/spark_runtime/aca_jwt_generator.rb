# typed: strict
# frozen_string_literal: true

module SparkRuntime
  class AcaJwtGenerator
    sig { params(app: String, deploy_user: String, private_pem: String, at_hash: T.nilable(String)).void }
    def initialize(app, deploy_user, private_pem, at_hash = nil)
      raise ArgumentError, "Missing private key configuration. Is WORKBENCH_ACA_JWT_PRIVATE_KEY set?" if private_pem.blank?

      @app = app
      @deploy_user = deploy_user
      @private_key = T.let(OpenSSL::PKey::EC.new(private_pem), OpenSSL::PKey::EC)
      @at_hash = at_hash
    end

    sig { returns(T::Hash[String, String]) }
    def plain_payload
      p = {
        "data" => {
          "app" => @app,
        },
        "aud" => "ACA",
        "exp" => 8.hours.from_now.to_i,
        "iss" => "GitHub",
        "sub" => @deploy_user,
      }

      p["at_hash"] = @at_hash if @at_hash

      p
    end

    sig { returns(String) }
    def jwt
      # if this algorithm changes, also change #token_at_hash in app/controllers/runtime/auth_controller.rb
      JWT.encode(plain_payload, @private_key, "ES384")
    end
  end
end
