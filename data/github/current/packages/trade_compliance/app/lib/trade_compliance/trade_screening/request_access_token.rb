# typed: strict
# frozen_string_literal: true

module TradeCompliance::TradeScreening
  class RequestAccessToken

    ERR_MSGS = T.let({
      400 => "Bad Request please contact @trade-compliance to review if the request has changed",
      401 => "Unauthorized due to"
    }.freeze, T::Hash[Integer, T.untyped])
    LIVE_AUTHENTICATION_TOKEN_CACHE_KEY = T.let("trade_controls:sdn:live_api_authn_token".freeze, String)
    EIS_AUTHENTICATION_TOKEN_CACHE_KEY = T.let("trade_controls:sdn:eis_authn_token".freeze, String)
    TTL = T.let(8.hours, Integer)

    sig { returns(String) }
    def self.for_eis
      return get_access_token(resource: GitHub.sdn_resource_eis) unless valid_authn_enc_key?
      # if fetch fails to find the cached then create a new cache token and return it.
      # if it found the key it will return directly then decrypt it.

      # record the start time so we monitor how long it takes to get a cached token
      start_time = GitHub::Dogstats.monotonic_time

      cache_exists = T.let(true, T::Boolean)
      encrypted_token = GitHub.cache.fetch(EIS_AUTHENTICATION_TOKEN_CACHE_KEY, stats_key: "#{EIS_AUTHENTICATION_TOKEN_CACHE_KEY}.cache", ttl: TTL) do
        cache_exists = false
        token = get_access_token(resource: GitHub.sdn_resource_eis)
        encrypt_token(token)
      end

      decrypted_token = decrypt_token(encrypted_token)
      if cache_exists
        log_success(start_time: start_time, token_type: "cached")
      end

      decrypted_token
    rescue RbNaCl::CryptoError
      GitHub.dogstats.increment("sdn_eis_access_token.read.decrypt_error")
      ""
    end

    sig { returns(String) }
    def self.for_live_api
      return get_access_token(resource: GitHub.sdn_resource_live_api) unless valid_authn_enc_key?
      # if fetch fails to find the cached then create a new cache token and return it.
      # if it found the key it will return directly then decrypt it.

      # record the start time so we monitor how long it takes to get a cached token
      start_time = GitHub::Dogstats.monotonic_time

      cache_exists = T.let(true, T::Boolean)
      encrypted_token = GitHub.cache.fetch(LIVE_AUTHENTICATION_TOKEN_CACHE_KEY, stats_key: "#{LIVE_AUTHENTICATION_TOKEN_CACHE_KEY}.cache", ttl: TTL) do
        cache_exists = false
        token = get_access_token(resource: GitHub.sdn_resource_live_api)
        encrypt_token(token)
      end

      decrypted_token = decrypt_token(encrypted_token)
      if cache_exists
        log_success(start_time: start_time, token_type: "cached")
      end

      decrypted_token
    rescue RbNaCl::CryptoError
      GitHub.dogstats.increment("sdn_live_access_token.read.decrypt_error")
      ""
    end

    # retrieve a fresh token regardless of current cached value then cache the new received value.
    sig { void }
    def self.force_new_token_for_eis
      token = get_access_token(resource: GitHub.sdn_resource_eis)
      return unless valid_authn_enc_key?
      encrypted_token = encrypt_token(token)
      GitHub.cache.set(EIS_AUTHENTICATION_TOKEN_CACHE_KEY, encrypted_token, TTL)
    end

    # retrieve a fresh token regardless of current cached value then cache the new received value.
    sig { void }
    def self.force_new_token_for_live_api
      token = get_access_token(resource: GitHub.sdn_resource_live_api)
      return unless valid_authn_enc_key?
      encrypted_token = encrypt_token(token)
      GitHub.cache.set(LIVE_AUTHENTICATION_TOKEN_CACHE_KEY, encrypted_token, TTL)
    end

    sig { returns(String) }
    def self.sdn_authentication_token_key
      return "" unless GitHub.sdn_authentication_token_key.respond_to?(:force_encoding)

      GitHub.sdn_authentication_token_key.b
    end

    class << self

      private

      sig { params(resource: String).returns(String) }
      def get_access_token(resource:)
        # record the start time so we monitor how long it takes to get a token
        start_time = GitHub::Dogstats.monotonic_time

        body = [
          "client_id=#{GitHub.sdn_authentication_client_id}",
          "client_secret=#{GitHub.sdn_authentication_client_secret}",
          "grant_type=client_credentials",
          "resource=#{resource}"
        ].join("&")
        connection = GitHub::FaradayClient::External.new(url: GitHub.sdn_authentication_base_url) { |f| f.adapter Faraday.default_adapter }
        resp = connection.post do |req|
          req.url "#{GitHub.sdn_authentication_tenant_id}/oauth2/token"
          req.headers["Content-Type"] = "application/x-www-form-urlencoded"
          req.body = body
        end
        if resp.status != 200
          err_desc = JSON.parse(resp.body).dig("error_description")
          msg = if err_desc.include?("Unauthorized") || err_desc.include?("Invalid client secret")
            "Invalid client credentials"
          else
            "Unknown error"
          end
          log_failure(reason: msg, start_time: start_time, token_type: "new")
          raise SDNAuthenticationError, "#{ERR_MSGS[resp.status]} #{msg}"
        end

        log_success(start_time: start_time, token_type: "new")
        GitHub::JSON.parse(resp.body)["access_token"]
      end

      sig { params(plain_token: String).returns(String) }
      def encrypt_token(plain_token)
        box = RbNaCl::SimpleBox.from_secret_key(sdn_authentication_token_key)
        encrypted_token = box.encrypt(plain_token)
      end

      sig { params(encrypted_token: String).returns(String) }
      def decrypt_token(encrypted_token)
        box = RbNaCl::SimpleBox.from_secret_key(sdn_authentication_token_key)
        plain_token = box.decrypt(encrypted_token)
      end

      sig { returns(T::Boolean) }
      def valid_authn_enc_key?
        sdn_authentication_token_key.present?
      end

      sig { params(start_time: Numeric, token_type: String).void }
      def log_success(start_time:, token_type:)
        # This will allow us to monitor the time (value) it takes to get a token type
        GitHub.dogstats.timing_since("sdn_api.request_#{token_type}_token.time", start_time)

        # This will allow us to monitor the number of success requests for token type
        GitHub.dogstats.increment(
          "sdn_api.request_#{token_type}_token.success",
        )
      end

      sig { params(reason: String, start_time: Numeric, token_type: String).void }
      def log_failure(reason:, start_time:, token_type:)
        GitHub.dogstats.timing_since("sdn_api.request_#{token_type}_token.time", start_time)

        # This will allow us to monitor the number of failed requests
        # and the reasons for the failures
        GitHub.dogstats.increment(
          "sdn_api.request_#{token_type}_token.failed",
          tags: ["reason: #{reason}"],
        )
      end
    end
  end
end
