# typed: strict
# frozen_string_literal: true

module SocialLogin
  class OpenIdConfiguration
    SIGNUP_KV_IDENTIFIER = T.let("social_signup", String)
    CACHE_CONTROL = "cache-control"
    EXPIRE_DEFAULT = T.let(1.day,  ActiveSupport::Duration)
    # https://rubular.com/r/ix0fHAItB0DTAA
    MAX_AGE = /[.+,]*max-age[\s]*=[\s]*(\d+)[,.+]*/

    # TODO - why is this so long?
    # looks like it's used for :user_social_identity and :social_accrual session expiration
    REQUEST_TIMEOUT = T.let(10.minutes, ActiveSupport::Duration)

    HOST = T.let(Rails.env.development? ? GitHub.host_name : GitHub.url + "/", String)
    GOOGLE_DISCOVERY_DOC_URI = T.let("#{GitHub.google_social_host_name}/.well-known/openid-configuration", String)
    GOOGLE_INITIATE_URI = T.let("#{GitHub.google_social_host_name}/o/oauth2/v2/auth", String)
    GOOGLE_ISSUERS = T.let(["#{GitHub.google_social_host_name}", "accounts.google.com"], T::Array[String])

    APPLE_DISCOVERY_DOC_URI = T.let("#{GitHub.apple_social_host_name}/.well-known/openid-configuration", String)
    APPLE_INITIATE_URI = T.let("#{GitHub.apple_social_host_name}/auth/authorize", String)
    APPLE_VALIDATE_TOKEN_URI = T.let("#{GitHub.apple_social_host_name}/auth/token", String)
    APPLE_ISSUER = T.let("#{GitHub.apple_social_host_name}", String)

    class Error < StandardError; end

    GOOGLE = "google"
    APPLE = "apple"

    PROVIDER_ID_MAP = T.let({
      GOOGLE => 1,
      APPLE => 2
    }.freeze, T::Hash[String, Integer])

    ID_PROVIDER_MAP = T.let({
      1 => GOOGLE,
      2 => APPLE
    }.freeze, T::Hash[Integer, String])

    #  Returns the integer enum value for a provider, or nil if not found
    sig { params(provider_key: String).returns(T.nilable(Integer)) }
    def self.provider_id(provider_key)
      PROVIDER_ID_MAP[provider_key]
    end


    #  Returns the integer enum value for a provider, or nil if not found
    sig { params(provider_enum: Integer).returns(T.nilable(String)) }
    def self.provider_value(provider_enum)
      ID_PROVIDER_MAP[provider_enum]
    end

    sig { params(provider_key: String).returns(T::Boolean) }
    def self.is_apple_provider?(provider_key)
      provider_key == APPLE
    end

    # Returns a config hash for the given provider_key (currently only google supported)
    sig { params(provider_key: String).returns(T::Hash[String, T.untyped]) }
    def self.settings(provider_key)
      case provider_key
      when GOOGLE
        {
          "discovery_uri" => GOOGLE_DISCOVERY_DOC_URI,
          "initiate_uri" => GOOGLE_INITIATE_URI,
          "callback_uri" => generate_redirect_uri(GOOGLE),
          "client_id" => GitHub.google_social_client_id,
          "client_secret" => GitHub.google_social_client_secret,
          "issuer" => GitHub.google_social_host_name,
          "issuer_list" => GOOGLE_ISSUERS,
        }
      when APPLE
        {
          "discovery_uri" => APPLE_DISCOVERY_DOC_URI,
          "initiate_uri" => APPLE_INITIATE_URI,
          "callback_uri" => generate_redirect_uri(APPLE),
          "client_id" => GitHub.apple_social_client_id,
          "issuer" => GitHub.apple_social_host_name,
          "issuer_list" => [APPLE_ISSUER],
        }
      else
        raise ArgumentError, "Unknown OIDC provider: \\#{provider_key}"
      end
    end

    # Returns the OIDC initiate URI for the specified provider
    sig { params(provider_key: String, state: String, nonce: String, code_challenge: String).returns(String) }
    def self.build_initiate_uri(provider_key, state, nonce, code_challenge)
      settings = settings(provider_key)
      uri = URI(settings["initiate_uri"])

      case provider_key
      when GOOGLE
        uri.query = URI.encode_www_form({
          "client_id": settings["client_id"],
          "response_type": "code",
          redirect_uri: settings["callback_uri"],
          scope: "openid email profile",
          state: state,
          nonce: nonce,
          code_challenge: code_challenge,
          code_challenge_method: "S256"
        })
      when APPLE
        uri.query = URI.encode_www_form({
          "client_id": settings["client_id"],
          redirect_uri: settings["callback_uri"],
          nonce: nonce,
          state: state,
          scope: "email",
          response_mode: "form_post",
          response_type: "code",
        })
      end

      uri.to_s
    end

    # Validates claims and exchanges code for tokens for the specified provider
    # NOTE: An ID Token is a cryptographically signed JWT. Normally, you must validate it before use.
    # Because this code exchanges directly with Google over HTTPS using your client secret, you can trust
    # the token's authenticity here. If you pass the ID token to other systems, those systems MUST validate it.
    sig { params(provider_key: String, code_verifier: String, code: String).returns(T::Hash[String, T.untyped]) }
    def self.validate_and_exchange_claims(provider_key, code_verifier, code)
      settings = settings(provider_key)
      oidc_config, err = for_provider(provider_key, settings["discovery_uri"])
      raise Error, "Error fetching OIDC configuration: #{err}" if err
      raise Error, "OIDC configuration is nil" if oidc_config.nil?
      base_uri = oidc_config["token_endpoint"]
      raise Error, "OIDC configuration missing token_endpoint" unless base_uri
      jwks_uri = oidc_config["jwks_uri"]
      raise Error, "OIDC configuration missing jwks_uri" unless jwks_uri
      response = case provider_key
      when GOOGLE
        get_google_response(settings, base_uri, code_verifier, code)
      when APPLE
        get_apple_response(settings, base_uri, code)
      end

      if response.status != 200
        raise Error, "#{provider_key} Token endpoint error: #{response.body}"
      end

      id_token = JSON.parse(response.body)["id_token"]
      raise Error, "Missing id_token in response" unless id_token

      # Decode the JWT without strict signature validation (see comment above)
      # This is safe here because the token is received directly from Google over HTTPS using our client secret.
      jwt_claims, jwt_header = JWT.decode(id_token, nil, false, {})
      kid = jwt_header["kid"]

      jwks, err = get(jwk_key(jwks_uri), jwks_uri)

      raise Error, "Error fetching JWKS: #{err}" if err
      raise Error, "JWKS is empty" if jwks.nil?

      keys = jwks["keys"]
      public_key = public_key_for_kid(keys, kid)
      # Now verify the JWT signature and claims
      jwt_claims, _ = begin JWT.decode(
        id_token,
        public_key,
        true,
        {
          algorithm: "RS256",
          aud: settings["client_id"],
          iss: settings["issuer_list"],
          verify_aud: true,
          verify_iss: true,
          verify_expiration: true,
        }
      )
      rescue JWT::DecodeError
        raise Error, "JWT decode error"
      end

      jwt_claims.with_indifferent_access
    end

    # Returns OIDC::Configuration
    sig { params(provider_key: String, uri: String).returns(T::Array[T::Hash[String, T.untyped]]) }
    def self.for_provider(provider_key, uri)
      get(configuration_key(provider_key), uri)
    end

    # Public: Gets the KV key associated with the configuration
    #
    # oidc_provider_key - is the provider key to get the IdP OIDC configuration endpoint
    #
    # Returns String
    sig { params(oidc_provider_key: String).returns(String) }
    def self.configuration_key(oidc_provider_key)
      "social_sisu:openid_config:#{oidc_provider_key}"
    end

    sig { params(jwk_uri: T.untyped).returns(String) }
    def self.jwk_key(jwk_uri)
      "social_sisu:jwk:#{jwk_uri}"
    end

    sig { params(client_id: String).returns(String) }
    def self.client_secret_key(client_id)
      "social_sisu:client_secret:#{client_id}"
    end

    # Private: Get the configuration value from a cache
    #
    # key - the key for the value in a cache
    # url - is the url to fetch the values from could be a common endpoint or a keys endpoint
    #
    # Returns [Hash, error] - the parsed config hash and any error encountered
    sig { params(key: String, url: String).returns(T::Array[T::Hash[String, T.untyped]]) }
    def self.get(key, url)
      value = GitHub::Authentication::KV.store.get(key).value { nil }
      begin
        value, error = set(key, url) unless value
        return [{}, error] if error
        [JSON.parse(value), nil]
      rescue JSON::ParserError => e
        GitHub.logger.error({ :exception => e, "code.function" => "OIDC::Cache.get" })
        error = Error.new("Problem parsing JSON from an IdP")
        Failbot.report_user_error(error)
        [{}, error]
      end
    end
    private_class_method :get

    # Private: Set the configuration value in a cache
    #
    # key - the key for the value in a cache
    # url - is the url to fetch the values from could be a common endpoint or a keys endpoint
    #
    # Returns [value, error] - the value set and any error encountered
    sig { params(key: String, url: String).returns(T::Array[T::Hash[String, T.untyped]]) }
    def self.set(key, url)
      expires, value, error = fetch(url)
      ActiveRecord::Base.connected_to(role: :writing) do
        GitHub::Authentication::KV.store.set(key, value, expires: expires) unless error
      end
      [value, error]
    end
    private_class_method :set

    # Private: Fetches the OpenId Connect configuration or signing keys for an IdP. The
    # configuration contains several important values, including:
    #
    #   authorization_endpoint
    #   token_endpoint
    #   token_endpoint_auth_methods_supported
    #   jwks_uri
    #   response_types_supported
    #   response_modes_supported
    #   subject_types_supported
    #   id_token_signing_alg_values_supported
    #   scopes_supported
    #   issuer
    #   claims_supported
    #   microsoft_multi_refresh_token
    #   check_session_iframe
    #   end_session_endpoint
    #   userinfo_endpoint
    #
    # url - is the url to fetch the values from could be a common endpoint or a keys endpoint
    #
    # Return DateTime, String

    # The configuration contains several important values, including:
    #   authorization_endpoint, token_endpoint, jwks_uri, userinfo_endpoint, etc.
    # url - is the url to fetch the values from (could be a config or keys endpoint)
    # Returns [expires, value, error] - expiration time, response body, and any error
    sig { params(url: String).returns(T::Array[T.untyped]) }
    def self.fetch(url)
      connection = GitHub::FaradayClient.external("SocialLogin::OpenIdConfiguration", url)
      response = connection.get do |request|
        request.headers["Content-Type"] = "application/json"
      end
      [get_expire_date(response.headers), response.body, nil]
    rescue Faraday::Error => e
      GitHub.logger.error({ :exception => e, "code.function" => "OIDC::Cache.fetch" })
      error = Error.new("Problem fetching data from an IdP.")
      Failbot.report_user_error(error)
      [nil, nil, error]
    end
    private_class_method :fetch

    # Private: Parse the max-age from a header to set the expires date in a cache
    # headers - return result headers
    # Returns DateTime - expiration time for the cache
    sig { params(headers: T.untyped).returns(DateTime) }
    def self.get_expire_date(headers)
      if headers && cache_control = headers[CACHE_CONTROL].presence
        if (match = cache_control.match(MAX_AGE))
          return match[1].to_i.seconds.from_now.to_datetime
        end
      end
      EXPIRE_DEFAULT.from_now.to_datetime
    end
    private_class_method :get_expire_date

    # Finds and constructs the OpenSSL public key for a given key ID (kid) from a JWKS.
    #
    # jwks - The array of JWK hashes as returned by fetch_jwks.
    # kid  - The key ID to look for in the JWKS.
    #
    # Returns an OpenSSL::PKey::RSA public key for verifying JWT signatures.
    # Raises StandardError if the key is not found or cannot be constructed.
    sig { params(jwks: T::Array[T::Hash[String, T.untyped]], kid: String).returns(OpenSSL::PKey::RSA) }
    def self.public_key_for_kid(jwks, kid)
      # Find the JWK with the matching key ID
      jwk = jwks.find { |key| key["kid"] == kid }
      raise StandardError, "Unable to find matching JWK for kid: #{kid}" unless jwk
      # Decode the modulus (n) and exponent (e) from base64url (no padding)
      n = Base64.urlsafe_decode64(jwk["n"])
      e = Base64.urlsafe_decode64(jwk["e"])
      # Construct the RSA public key
      key = OpenSSL::PKey::RSA.new
      key.set_key(OpenSSL::BN.new(n, 2), OpenSSL::BN.new(e, 2), nil)
      key
    end

    sig { params(provider: String).returns(String) }
    def self.generate_redirect_uri(provider)
      "#{HOST}sessions/social/#{provider}/callback"
    end
    private_class_method :generate_redirect_uri

    sig { params(settings: T::Hash[String, String], base_uri: String, code_verifier: String, code: String).returns(T.untyped) }
    def self.get_google_response(settings, base_uri, code_verifier, code)
      connection = GitHub::FaradayClient.external("SocialLogin::OpenIdConfiguration", base_uri)
      payload = { code_verifier: code_verifier, code: code }.merge({
        grant_type: "authorization_code",
        client_id: settings["client_id"],
        client_secret: settings["client_secret"],
        redirect_uri: settings["callback_uri"]
      })

      response = connection.post do |request|
        request.headers["Content-Type"] = "application/x-www-form-urlencoded"
        request.body = payload.to_query
      end

      response
    end
    private_class_method :get_google_response

    sig { params(settings: T::Hash[String, String], base_uri: String, code: String).returns(T.untyped) }
    def self.get_apple_response(settings, base_uri, code)
      connection = GitHub::FaradayClient.external(
        "SocialLogin::OpenIdConfiguration",
        base_uri,
        request: {
          timeout:      10,
          open_timeout:  5
        }
      )

      client_secret = generate_apple_client_secret(T.must(settings["client_id"]))

      payload = {
        client_id: settings["client_id"],
        client_secret: client_secret,
        code: code,
        grant_type: "authorization_code",
        redirect_uri: settings["callback_uri"],
      }

      response = connection.post do |request|
        request.headers["Content-Type"] = "application/x-www-form-urlencoded"
        request.body = payload.to_query
      end

      response
    end
    private_class_method :get_apple_response

    sig { params(client_id: String).returns(String) }
    def self.generate_apple_client_secret(client_id)
      kv_key = client_secret_key(client_id)
      secret = GitHub::Authentication::KV.store.get(kv_key).value { nil }
      # Store the client secret in KV
      if secret.nil?
        expiration = Time.now + 30.days
        key = OpenSSL::PKey::EC.new(GitHub.apple_social_private_key)
        payload = {
          iss: GitHub.apple_social_team_id,
          iat: Time.now.to_i,
          exp: expiration.to_i,
          aud: APPLE_ISSUER,
          sub: client_id,
        }
        headers = { kid: GitHub.apple_social_key_id }
        secret = JWT.encode(payload, key, "ES256", headers)

        ActiveRecord::Base.connected_to(role: :writing) do
          GitHub::Authentication::KV.store.set(kv_key, secret, expires: expiration)
        end
      end

      secret
    end
    private_class_method :generate_apple_client_secret
  end

end
