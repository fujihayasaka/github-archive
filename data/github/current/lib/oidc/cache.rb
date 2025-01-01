# typed: false
# frozen_string_literal: true

require "oidc/configuration"
require "oidc/keys"
require "active_support/time"

# This is class is implementing a read through cache.  It depends on the information stored
# in the OIDCProvider object and will automatically cache the information.  When the information
# is not in the cache it will interrogate and common endpoint to get the OIDC info and cache it for
# the length of time specified in the Cache-Control header.
module OIDC
  class Cache
    COMMON = OIDC::Configuration::COMMON
    CACHE_CONTROL = "cache-control"
    EXPIRE_DEFAULT = 1.day
    # https://rubular.com/r/ix0fHAItB0DTAA
    MAX_AGE = /[.+,]*max-age[\s]*=[\s]*(\d+)[,.+]*/

    class OidcCacheRefreshError < StandardError; end

    # Public: Method to get the cached configuration.
    #   If one does not exist it will be read from an IdP common endpoint and stored.
    #
    # oidc_provider_key - is the provider key to get the IdP OIDC configuration endpoint, ex :azure, :okta
    # endpoint - If the tenant id is passed configuration will be set as tenanted not common
    #
    # Returns OIDC::Configuration
    def self.get_configuration(oidc_provider_key, endpoint = COMMON)
      url = GitHub.oidc_providers[oidc_provider_key]["config_url"]
      configuration, error = get(configuration_key(oidc_provider_key), url)
      Configuration.new(configuration, endpoint, error: error)
    end

    # Public: Method to get the cached keys.
    #   If those do not exist they will be read from an IdP common endpoint and stored.
    #
    # oidc_provider_key - is the provider key to get the IdP OIDC configuration endpoint, ex :azure, :okta
    # configuration - a configuration to get the keys signing key endpoint from
    # bust_cache - if true the cache will be ignored and the keys will be fetched from the endpoint
    #
    # Returns Keys
    def self.get_signing_keys(oidc_provider_key, configuration, bust_cache = false)
      keys, error = get(signing_keys_key(oidc_provider_key), URI(configuration.signing_keys_endpoint))
      keys_object = Keys.new(keys, error: error)
      if bust_cache
        # rubocop:todo GitHub/DoNotUseGlobalKv
        recently_refreshed = GitHub.kv.get("#{oidc_provider_key}.recently_refreshed").value { false }
        # rubocop:enable GitHub/DoNotUseGlobalKv
        return keys_object if recently_refreshed
        # We do set and then get so that we have proper json parsing error validation
        # The additional overhead is worth it to not complicate set
        set(oidc_provider_key, URI(configuration.signing_keys_endpoint))
        keys, error = get(oidc_provider_key, URI(configuration.signing_keys_endpoint))
        keys_object = Keys.new(keys, error: error)
        # rubocop:todo GitHub/DoNotUseGlobalKv
        GitHub.kv.set("#{oidc_provider_key}.recently_refreshed", "true", expires: 5.minutes.from_now)
        # rubocop:enable GitHub/DoNotUseGlobalKv
      end

      keys_object
    end

    # Public: Gets the KV key associated with the configuration
    #
    # oidc_provider_key - is the provider key to get the IdP OIDC configuration endpoint
    #
    # Returns String
    def self.configuration_key(oidc_provider_key)
      "oidc:config:#{oidc_provider_key}"
    end

    # Public: Gets the KV key associated with the configuration
    #
    # oidc_provider_key - is the provider key to get the IdP OIDC configuration endpoint
    #
    # Returns String
    def self.signing_keys_key(oidc_provider_key)
      "oidc:keys:#{oidc_provider_key}"
    end

    # Private: Get the configuration value from a cache
    #
    # key - the key for the value in a cache
    # url - is the url to fetch the values from could be a common endpoint or a keys endpoint
    #
    # Return String
    def self.get(key, url)
      value = GitHub.kv.get(key).value { nil } # rubocop:todo GitHub/DoNotUseGlobalKv

      begin
        value, error = set(key, url) unless value

        return nil, error if error

        [JSON.parse(value), nil]
      rescue JSON::ParserError => e
        GitHub.logger.error({ :exception => e, "code.function" => "OIDC::Cache.get" })

        # raise generic FetchError for Sentry
        # more details can be found in Splunk
        error = OidcCacheRefreshError.new("Problem parsing JSON from an IdP")
        Failbot.report_user_error(error)

        [nil, error]
      end
    end
    private_class_method :get

    # Private: Set the configuration value in a cache
    #
    # key - the key for the value in a cache
    # url - is the url to fetch the values from could be a common endpoint or a keys endpoint
    #
    # Return String - set value
    def self.set(key, url)
      expires, value, error = fetch(url)

      GitHub.logger.info(
        "Successfully refreshed OIDC information",
        "code.function" => "OIDC::Cache.set",
        "gh.external_identities.type" => "fetch",
        "gh.external_identities.cache_key" => key,
        "gh.external_identities.cache_body" => value,
        "gh.external_identities.cache_expires" => expires,
      ) unless error

      ActiveRecord::Base.connected_to(role: :writing) do
        GitHub.kv.set(key, value, expires: expires) unless error # rubocop:todo GitHub/DoNotUseGlobalKv
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
    def self.fetch(url)
      response = Faraday.get(url)

      [get_expire_date(response.headers), response.body, nil]
    rescue Faraday::Error => e
      GitHub.logger.error({ :exception => e, "code.function" => "OIDC::Cache.fetch" })

      # raise generic FetchError for Sentry
      # more details can be found in Splunk
      error = OidcCacheRefreshError.new("Problem fetching data from an IdP.")
      Failbot.report_user_error(error)

      [nil, nil, error]
    end
    private_class_method :fetch

    # Private: Parse the max-age from a header to set the expires date in a cache
    #
    # headers - return result headers
    #
    # Return DateTime
    def self.get_expire_date(headers)
      if headers && cache_control = headers[CACHE_CONTROL].presence
        if cache_control.match(MAX_AGE)
          return $1.to_i.seconds.from_now
        end
      end

      EXPIRE_DEFAULT.from_now
    end
    private_class_method :get_expire_date
  end
end
