# typed: strict
# frozen_string_literal: true

require "monolith-twirp-features-featureflaghub"

module FeatureManagement
  class FeatureFlagHubClient
    SERVICE_NAME = "feature_management"
    DEFAULT_TIMEOUT = 3.0 # seconds
    DEFAULT_OPEN_TIMEOUT = 2.0 # seconds
    DEFAULT_MAX_RETRIES = 0
    TELEMETRY_PREFIX = "gh.feature_management.feature_flag_hub_client"

    sig { returns(Float) }
    attr_reader :timeout, :open_timeout

    sig { returns(Integer) }
    attr_reader :max_retries

    sig { params(timeout: T.nilable(Float), open_timeout: T.nilable(Float), max_retries: T.nilable(Integer)).void }
    def initialize(timeout = nil, open_timeout = nil, max_retries = nil)
      @timeout = T.let(timeout || DEFAULT_TIMEOUT, Float)
      @open_timeout = T.let(open_timeout || DEFAULT_OPEN_TIMEOUT, Float)
      @max_retries = T.let(max_retries || DEFAULT_MAX_RETRIES, Integer)
      @client = T.let(client, MonolithTwirp::Features::FeatureFlagHub::V1::SyncAPIClient)
    end

    sig { returns(MonolithTwirp::Features::FeatureFlagHub::V1::SyncAPIClient) }
    def client
      MonolithTwirp::Features::FeatureFlagHub::V1::SyncAPIClient.new(connection)
    end

    sig { returns(GitHub::FaradayClient::Internal) }
    def connection
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
        conn.use ::GitHub::FaradayMiddleware::Datadog, stats: GitHub.dogstats, service_name: SERVICE_NAME, custom_tags: ["service_endpoint:features.featureflaghub.v1.SyncAPI"]
        conn.use ::GitHub::FaradayMiddleware::Resilient, name: SERVICE_NAME
        conn.adapter :typhoeus
      end
    end

    sig { returns(String) }
    def get_hmac_key
      key = GitHub.feature_management_feature_flag_hub_hmac_key
      raise FeatureManagement::FeatureFlagHubClientError.new(:environment_error, "Hmac key cannot be nil") if key.nil?
      key
    end

    sig { returns(String) }
    def get_url
      url = GitHub.feature_management_feature_flag_hub_url
      raise FeatureManagement::FeatureFlagHubClientError.new(:environment_error, "Feature Flag Hub url cannot be nil") if url.nil?
      url
    end

    sig { params(feature_name: String, sync_correlation_id: String, first_batch: T::Boolean, last_batch: T::Boolean, actors: T::Array[String]).returns(NilClass) }
    def bulk_sync_feature_actors(feature_name, sync_correlation_id, first_batch, last_batch, actors)
      request = MonolithTwirp::Features::FeatureFlagHub::V1::BulkSyncFeatureActorsRequest.new(
        {
          actors: actors,
          feature_name: feature_name,
          sync_correlation_id: sync_correlation_id,
          is_last_batch: last_batch,
          is_first_batch: first_batch,
        })
      resp = @client.bulk_sync_feature_actors(request)
      raise FeatureManagement::FeatureFlagHubClientError.new(resp.error.code, resp.error.msg, resp.error.meta) if resp.error
      nil
    end
  end
end
