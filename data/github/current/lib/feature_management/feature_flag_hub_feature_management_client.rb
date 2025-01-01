# typed: strict
# frozen_string_literal: true
require "faraday"
require "faraday_middleware"

module FeatureManagement
  class FeatureFlagHubFeatureManagementClient
    extend T::Sig
    SERVICE_NAME = "feature_management"
    DEFAULT_TIMEOUT = 5.0 # seconds
    DEFAULT_OPEN_TIMEOUT = 2.0 # seconds
    DEFAULT_MAX_RETRIES = 0
    FEATURE_FLAGS_SERVICE_ENDPOINT = "feature_management.feature_flags.management.v3.FeatureFlags"
    TELEMETRY_PREFIX = "gh.feature_management.feature_flags_client"

    sig { returns(Float) }
    attr_reader :timeout, :open_timeout

    sig { returns(Integer) }
    attr_reader :max_retries

    sig { params(timeout: T.nilable(Float), open_timeout: T.nilable(Float), max_retries: T.nilable(Integer)).void }
    def initialize(timeout = nil, open_timeout = nil, max_retries = nil)
      @timeout = T.let(timeout || DEFAULT_TIMEOUT, Float)
      @open_timeout = T.let(open_timeout || DEFAULT_OPEN_TIMEOUT, Float)
      @max_retries = T.let(max_retries || DEFAULT_MAX_RETRIES, Integer)
      @client = T.let(client, GitHub::FaradayClient::Internal)
    end

    sig { params(feature_name: String).returns(FeatureManagement::Management::FeatureFlag) }
    def get_feature_flag(feature_name)
      url = "#{FEATURE_FLAGS_SERVICE_ENDPOINT}/GetFeatureFlag"
      body = { name: feature_name }.to_json
      response = @client.post(url) do |req|
        req.body = body
      end
      process_featureflag_response(response)
    end

    sig { params(feature: FeatureManagement::Management::FeatureFlag).returns(FeatureManagement::Core::Operation) }
    def create_feature_flag(feature)
      feature.apply_defaults!
      url = "#{FEATURE_FLAGS_SERVICE_ENDPOINT}/CreateFeatureFlag"
      body = { feature: feature }.to_json
      response = @client.post(url) do |req|
        req.body = body
      end
      process_operation_response_and_wait(response)
    end

    sig { params(feature: FeatureManagement::Management::FeatureFlag, update_mask: String).returns(FeatureManagement::Core::Operation) }
    def update_feature_flag(feature, update_mask)
      feature.apply_defaults!
      url = "#{FEATURE_FLAGS_SERVICE_ENDPOINT}/UpdateFeatureFlag"
      body = { feature: feature, update_mask: update_mask }.to_json
      response = @client.post(url) do |req|
        req.body = body
      end
      process_operation_response_and_wait(response)
    end

    sig { params(feature_name: String).returns(FeatureManagement::Core::Operation) }
    def delete_feature_flag(feature_name)
      url = "#{FEATURE_FLAGS_SERVICE_ENDPOINT}/DeleteFeatureFlag"
      body = { name: feature_name }.to_json
      response = @client.post(url) do |req|
        req.body = body
      end
      process_operation_response_and_wait(response)
    end

    sig { params(id: String).returns(FeatureManagement::Core::Operation) }
    def get_operation(id)
      url = "#{FEATURE_FLAGS_SERVICE_ENDPOINT}/GetOperation"
      body = { id: id }.to_json
      response = @client.post(url) do |req|
        req.body = body
      end
      process_operation_response(response)
    end

    sig { returns(GitHub::FaradayClient::Internal) }
    def client
      GitHub::FaradayClient::Internal.new(get_url) do |conn|
        conn.options[:open_timeout] = @open_timeout
        conn.options[:timeout]      = @timeout

        conn.request :json
        conn.request :retry,
        max: @max_retries,
        backoff_factor:      1.2,
        methods:     [:post],
        retry_block: proc { GitHub.dogstats.increment("#{TELEMETRY_PREFIX}.request_retry.count", tags: []) }

        conn.use ::GitHub::FaradayMiddleware::RequestID
        conn.use GitHub::FaradayMiddleware::HMACAuth, hmac_key: get_hmac_key
        conn.use ::GitHub::FaradayMiddleware::Datadog, stats: GitHub.dogstats, service_name: SERVICE_NAME
        conn.use ::FeatureManagement::CurrentUser
        conn.use ::GitHub::FaradayMiddleware::Resilient, name: SERVICE_NAME
        conn.adapter :typhoeus
      end
    end

    sig { params(response: Faraday::Response).returns(FeatureManagement::Core::Operation) }
    def process_operation_response_and_wait(response)
      FeatureManagement::FeatureFlagHubClientUtil.process_response_error(response, false)
      data = JSON.parse(response.body)
      if response.status < 300 && data["done"] == true
        return FeatureManagement::Core::Operation.new(data["id"], data["done"], data["status_code"])
      end

      operation_id = data["id"]
      FeatureManagement::FeatureFlagHubClientUtil::process_pending_response_completion(@client, FEATURE_FLAGS_SERVICE_ENDPOINT, operation_id)
    end

    sig { params(response: Faraday::Response).returns(FeatureManagement::Core::Operation) }
    def process_operation_response(response)
      FeatureManagement::FeatureFlagHubClientUtil.process_response_error(response, false)
      data = JSON.parse(response.body)
      FeatureManagement::Core::Operation.new(data["id"], data["done"], data["status_code"])
    end

    sig { params(response: Faraday::Response).returns(FeatureManagement::Management::FeatureFlag) }
    def process_featureflag_response(response)
      data = JSON.parse(response.body)
      raise FeatureManagement::FeatureFlagHubAsyncOperationError.new(response.status, data["msg"], response.body) if response.status != 200
      f = FeatureManagement::Management::FeatureFlag.new(data["name"])
      f.parse(response.body)
    end

    sig { returns(String) }
    def get_hmac_key
      key = GitHub.feature_management_feature_flag_hub_mgmt_hmac_key
      raise FeatureManagement::FeatureFlagHubClientError.new(:environment_error, "Hmac key cannot be nil") if key.nil?
      key
    end

    sig { returns(String) }
    def get_url
      url = GitHub.feature_management_feature_flag_hub_url
      raise FeatureManagement::FeatureFlagHubClientError.new(:environment_error, "Feature Flag Hub url cannot be nil") if url.nil?
      url
    end
  end
end
