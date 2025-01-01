# typed: strict
# frozen_string_literal: true
require "faraday"
require "faraday_middleware"

module FeatureManagement
  class FeatureFlagHubSegmentMemberManagementClient
    extend T::Sig
    SERVICE_NAME = "feature_management"
    DEFAULT_TIMEOUT = 3.0 # seconds
    DEFAULT_OPEN_TIMEOUT = 2.0 # seconds
    DEFAULT_MAX_RETRIES = 0
    SEGMENT_MEMBER_SERVICE_ENDPOINT = "feature_management.feature_flags.management.v3.SegmentMembers"
    TELEMETRY_PREFIX = "gh.feature_management.segment_members_client"

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

    sig { params(feature_name: String, member_actor_ids: T::Array[String]).returns(FeatureManagement::Core::Operation) }
    def add_members(feature_name, member_actor_ids)
      segment_name = default_segment_name(feature_name)
      url = "#{SEGMENT_MEMBER_SERVICE_ENDPOINT}/AddMembers"
      body = { segment_name: segment_name, member_ids: member_actor_ids }.to_json
      response = @client.post(url) do |req|
        req.body = body
      end
      process_operation_response_and_wait(response, false)
    end

    sig { params(feature_name: String, member_actor_ids: T::Array[String]).returns(FeatureManagement::Core::Operation) }
    def remove_members(feature_name, member_actor_ids)
      segment_name = default_segment_name(feature_name)
      url = "#{SEGMENT_MEMBER_SERVICE_ENDPOINT}/RemoveMembers"
      body = { segment_name: segment_name, member_ids: member_actor_ids }.to_json
      response = @client.post(url) do |req|
        req.body = body
      end
      process_operation_response_and_wait(response, false)
    end

    sig { params(feature_name: String).returns(FeatureManagement::Core::Operation) }
    def remove_all_members(feature_name)
      segment_name = default_segment_name(feature_name)
      url = "#{SEGMENT_MEMBER_SERVICE_ENDPOINT}/RemoveAllMembers"
      body = { segment_name: segment_name }.to_json
      response = @client.post(url) do |req|
        req.body = body
      end
      process_operation_response_and_wait(response, true)
    end

    sig { params(id: String).returns(FeatureManagement::Core::Operation) }
    def get_operation(id)
      url = "#{SEGMENT_MEMBER_SERVICE_ENDPOINT}/GetOperation"
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

    sig { params(response: Faraday::Response, not_found_allowed: T::Boolean).returns(FeatureManagement::Core::Operation) }
    def process_operation_response_and_wait(response, not_found_allowed)
      FeatureManagement::FeatureFlagHubClientUtil.process_response_error(response, not_found_allowed)
      data = JSON.parse(response.body)
      if response.status < 300 && data["done"] == true
        return FeatureManagement::Core::Operation.new(data["id"], data["done"], data["status_code"])
      end

      operation_id = data["id"]
      FeatureManagement::FeatureFlagHubClientUtil::process_pending_response_completion(@client, SEGMENT_MEMBER_SERVICE_ENDPOINT, operation_id)
    end

    sig { params(response: Faraday::Response).returns(FeatureManagement::Core::Operation) }
    def process_operation_response(response)
      FeatureManagement::FeatureFlagHubClientUtil.process_response_error(response, false)
      data = JSON.parse(response.body)
      FeatureManagement::Core::Operation.new(data["id"], data["done"], data["status_code"])
    end

    sig { params(feature_name: String).returns(String) }
    def default_segment_name(feature_name)
      "_#{feature_name}"
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
