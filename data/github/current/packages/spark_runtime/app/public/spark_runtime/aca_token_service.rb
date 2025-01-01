# typed: strict
# frozen_string_literal: true

module SparkRuntime
  class AcaTokenService
    sig do
      params(
        user_session: T.untyped,
      ).returns([String, T.any(ActiveSupport::TimeWithZone, Time)])
    end
    def self.mint_raw_app_token(user_session:)
      return ["shhh", Time.at(0)] unless GitHub.flipper[:mint_spark_app_token].enabled?

      user = user_session.user
      app = ::Apps::Privileged.integration(:spark)

      new_access = app.grant(user, { user_session: user_session })
      token, _ = new_access.redeem
      expires_at = new_access.expires_at

      [token, expires_at]
    end

    sig do
      params(
        app_name: String,
        app_owner_login: String,
        user_session: T.untyped,
      ).returns(String)
    end
    def self.mint_encrypted_jwt(app_name:, app_owner_login:, user_session:)
      token, token_expires_at = mint_raw_app_token(user_session:)

      jwt = SparkRuntime::SdkJwtGenerator.new(
        token,
        token_expires_at,
        app_name,
        app_owner_login,
        user_session.user.display_login,
        GitHub.copilot_workbench_aca_jwt_private_key
      ).jwt

      GitHub.encrypt_spark_token(jwt)
    end

    sig { params(token: T.untyped).returns(String) }
    def self.token_at_hash(token)
      # logic taken from https://openid.net/specs/openid-connect-core-1_0.html#CodeIDToken
      # hash algorithm comes from SparkRuntime::AcaJwtGenerator

      # hash the token
      hashed_token = Digest::SHA384.digest(token)

      # take the first 128 bits/16 bytes
      hashed_token = hashed_token.byteslice(0, 16)

      # base64url-encode that
      Base64.urlsafe_encode64(hashed_token, padding: false)
    end
  end
end
