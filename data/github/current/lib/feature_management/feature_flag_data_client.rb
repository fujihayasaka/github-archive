# typed: strict
# frozen_string_literal: true

require "feature_management_feature_flags"

module FeatureManagement
  class FeatureFlagDataClient
    include GitHub::Memoizer

    SERVICE_NAME = "feature_management"
    DEFAULT_TIMEOUT = 3.0 # seconds
    DEFAULT_OPEN_TIMEOUT = 2.0 # seconds
    DEFAULT_MAX_RETRIES = 0
    TELEMETRY_PREFIX = "gh.feature_management.feature_flag_data_client"

    sig { params(timeout: T.nilable(Float), open_timeout: T.nilable(Float), max_retries: T.nilable(Integer)).void }
    def initialize(timeout = nil, open_timeout = nil, max_retries = nil)
      @timeout = T.let(timeout || DEFAULT_TIMEOUT, Float)
      @open_timeout = T.let(open_timeout || DEFAULT_OPEN_TIMEOUT, Float)
      @max_retries = T.let(max_retries || DEFAULT_MAX_RETRIES, Integer)
      @client = T.let(client, FeatureManagement::FeatureFlags::Data::V2::MonolithOptimizedChecksClient)
    end

    # Get enabled feature flags for a specific actor. Returns three arrays: [actor_enabled_flags, inherited_enabled_flags, possibly_enabled_flags]
    sig { params(actor_id: String).returns([T::Array[FeatureManagement::FeatureFlags::Data::V2::FeatureFlag], T::Array[FeatureManagement::FeatureFlags::Data::V2::FeatureFlag], T::Array[FeatureManagement::FeatureFlags::Data::V2::FeatureFlag]]) }
    def get_enabled_feature_flags_by_actor(actor_id)
      request = FeatureManagement::FeatureFlags::Data::V2::GetEnabledFeatureFlagsByActorRequest.new(actor: actor_id)
      response = @client.get_enabled_feature_flags_by_actor(request)

      unless response.error.nil?
        twirp_error = T.must(response.error)
        if twirp_error.meta[:status_code] == "429"
          raise FeatureManagement::FeatureFlagDataClientError.new(:rate_limited, "Rate limited by Feature Flag Data service")
        end
        return [[], [], []]
      end

      actor_enabled_flags = response.data.actor_enabled_flags.to_ary
      inherited_enabled_flags = response.data.inherited_enabled_flags.to_ary
      possibly_enabled_flags = response.data.possibly_enabled_flags.to_ary

      [actor_enabled_flags, inherited_enabled_flags, possibly_enabled_flags]
    rescue FeatureManagement::FeatureFlagDataClientError => e
      # We're just raising because above we're raising an error so that caller can handle it
      # appropriately (e.g. show a message in the UI).
      # If we don't rescue this exception here, it will get caught by the generic rescue below.
      raise
    rescue Faraday::TimeoutError, Faraday::ConnectionFailed, StandardError => e
      Failbot.report(e)
      [[], [], []]
    end

    private

    sig { returns(FeatureManagement::FeatureFlags::Data::V2::MonolithOptimizedChecksClient) }
    def client
      FeatureManagement::FeatureFlags::Data::V2::MonolithOptimizedChecksClient.new(connection)
    end

    sig { returns(GitHub::FaradayClient::Internal) }
    memoize def connection
      GitHub::FaradayClient::Internal.new(get_url) do |conn|
        conn.options[:open_timeout] = @open_timeout
        conn.options[:timeout]      = @timeout

        conn.request :retry,
        max: @max_retries,
        backoff_factor:      1.2,
        methods:     [:post],
        retry_block: proc { GitHub.dogstats.increment("#{TELEMETRY_PREFIX}.request_retry.count", tags: []) }

        conn.use ::GitHub::FaradayMiddleware::RequestID
        conn.use GitHub::FaradayMiddleware::HMACAuth, hmac_key: get_hmac_key
        conn.use ::FeatureManagement::FeatureFlagDataUser
        conn.use ::GitHub::FaradayMiddleware::Datadog, stats: GitHub.dogstats, service_name: SERVICE_NAME, custom_tags: ["service_endpoint:featuremanagement.featureflags.data.v2.ChecksAPI"]
        conn.use ::GitHub::FaradayMiddleware::Resilient, name: SERVICE_NAME
        conn.adapter :typhoeus
      end
    end

    sig { returns(String) }
    def get_hmac_key
      key = GitHub.feature_management_feature_flag_data_checks_hmac_shared_key
      raise FeatureManagement::FeatureFlagDataClientError.new(:environment_error, "Hmac key cannot be nil") if key.nil? && !GitHub.use_fm_lite?
      key
    end

    sig { returns(String) }
    def get_url
      url = GitHub.feature_management_feature_flag_data_url
      raise FeatureManagement::FeatureFlagDataClientError.new(:environment_error, "Feature Flag Data url cannot be nil") if url.nil?
      url
    end
  end
end
