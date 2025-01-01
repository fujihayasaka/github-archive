# typed: strict
# frozen_string_literal: true

module SparkRuntime
  class TokenService
    TOKEN_EXPIRATION_BUFFER = T.let(1.hour, T.untyped)

    # Returns a fully encrypted JWT to be sent to ACA.
    sig do
      params(
        user_session: T.untyped,
        app_name: String,
        app_owner_login: String,
      ).returns([String, T.any(ActiveSupport::TimeWithZone, Time)])
    end
    def self.encrypted_aca_jwt(user_session:, app_name:, app_owner_login:)
      token, token_expires_at = fetch_token(user_session)
      jwt = SparkRuntime::SdkJwtGenerator.new(
        token,
        token_expires_at,
        app_name,
        app_owner_login,
        user_session.user.display_login,
        GitHub.copilot_workbench_aca_jwt_private_key
      ).jwt

      [GitHub.encrypt_spark_token(jwt), token_expires_at]
    end

    sig do
      params(
        raw_header: T.nilable(String),
      ).returns(T.nilable([User, String]))
    end
    def self.decrypt_jwt_claims!(raw_header:)
      return if !raw_header || !raw_header.start_with?("Spark-Bearer ")

      encrypted_token = raw_header.split(" ")[1]
      return if !encrypted_token

      decrypted = GitHub.decrypt_spark_token(encrypted_token)

      jwt = JWT.decode(decrypted, nil, false)

      return unless jwt.is_a?(Array) && jwt.length == 2 && jwt[0].is_a?(Hash)

      token = jwt[0]["data"]["tkn"]
      app_user = jwt[0]["data"]["app_user"]

      user_result = user_from_token(token)
      return unless user_result.success?

      [user_result.user, app_user]
    end

    # Returns a raw app token encrypted using the CAPI encryption key. To be used for tokens sent to CAPI.
    sig do
      params(
        user_session: T.untyped,
      ).returns([String, T.any(ActiveSupport::TimeWithZone, Time)])
    end
    def self.encrypted_capi_token(user_session)
      token, token_expires_at = fetch_token(user_session)
      encrypted = GitHub.dotcom_capi_simple_box.encrypt(token)
      encoded = Base64.urlsafe_encode64(encrypted)

      [encoded, token_expires_at]
    end

    # Returns a raw app token encrypted using the Secret Scanning encryption key.
    sig do
      params(
        user_session: T.untyped,
      ).returns([String, T.any(ActiveSupport::TimeWithZone, Time)])
    end
    def self.encrypted_secret_scanning_token(user_session)
      token, token_expires_at = fetch_token(user_session)
      encoded = GitHub.encrypt_and_encode_token_for_secret_scanning(token)

      [encoded, token_expires_at]
    end

    # Returns a raw app token, to be used in Spark dev environment in some cases (EMU).
    #
    # Note that this is expected to be used once per Codespace, so we don't cache.
    # We don't want to risk having a short expiration from sharing, and the rate
    # of creation should be limited by being done only at Codespace creation/resume.
    sig do
      params(
        user: User
      ).returns([String, T.any(ActiveSupport::TimeWithZone, Time)])
    end
    def self.spark_token_for_development(user)
      mint_token(user)
    end

    sig { params(token: String).returns(String) }
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

    # Fetches a token from the cache, or mints a new one if necessary.
    sig do
      params(
        user_session: T.untyped,
      ).returns([String, T.any(ActiveSupport::TimeWithZone, Time)])
    end
    private_class_method def self.fetch_token(user_session)
      user = user_session.user
      cache_key = "app_token:#{user.id}"

      # the token needs to be encrypted at rest in the cache, but decrypted before going into the JWT (because the
      # entire JWT is encrypted)
      if cached = SparkRuntime::KV.store.get(cache_key).value!
        token_with_expiry = GitHub.decrypt_spark_token(cached)

        split_token = token_with_expiry.split("|")
        raw_token = split_token[0]
        token_expires_at = Time.iso8601(split_token[1])
      else
        raw_token, token_expires_at = mint_token(user, user_session)
        encrypted_token_with_expiry = GitHub.encrypt_spark_token("#{raw_token}|#{token_expires_at.iso8601}")

        ActiveRecord::Base.connected_to(role: :writing) do
          # subtract TOKEN_EXPIRATION_BUFFER only when storing it here. the KV store will not return a value for expired
          # entries, so this has the effect of expiring the token early while passing the actual expiration to consumers
          SparkRuntime::KV.store.set(cache_key, encrypted_token_with_expiry, expires: token_expires_at - TOKEN_EXPIRATION_BUFFER)
        end
      end

      [raw_token, token_expires_at]
    end

    # Mints a new token for the user.
    sig do
      params(
        user: User,
        user_session: T.untyped,
      ).returns([String, T.any(ActiveSupport::TimeWithZone, Time)])
    end
    private_class_method def self.mint_token(user, user_session = nil)
      app = ::Apps::Privileged.integration(:spark)

      options = user_session ? { user_session: user_session } : {}

      new_access = app.grant(user, options)
      token, _ = new_access.redeem
      expires_at = new_access.expires_at

      [token, expires_at]
    end

    sig do
      params(
        token: String,
      ).returns(GitHub::Authentication::Result)
    end
    private_class_method def self.user_from_token(token)
      api_auth = GitHub::Authentication::Attempt.new(
        allow_user_via_granular_actor: true,
        allow_integrations: true,
        from: :api_other,
        token: token,
        password_auth_blocked: true,
      )
      api_auth.result
    end
  end
end
