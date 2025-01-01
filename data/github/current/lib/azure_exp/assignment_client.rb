# typed: true
# frozen_string_literal: true

require "faraday"
require "net/http/persistent"
require "explore_feed/feeds/kv"

module AzureEXP
  class AssignmentRequestError < StandardError; end

  class AssignmentClient

    AZURE_EXP_PATH = "exp00451/a869f069-fe31-46f4-8784-c164f79eb133-githubprod/api/v1/tas"
    EXP_URI = "https://default.exp-tas.com/"
    CONNECTION_OPEN_TIMEOUT = 2
    CONNECTION_TIMEOUT = 5
    USER_AGENT = "Microsoft.VariantAssignment.Client"
    SERVICE_NAME = "azure_exp"

    def initialize(assignment_path = AZURE_EXP_PATH, namespace: nil, pool_size: Net::HTTP::Persistent::DEFAULT_POOL_SIZE, timeout: CONNECTION_TIMEOUT, open_timeout: CONNECTION_OPEN_TIMEOUT, disable_cache: false)
      @assignment_path = assignment_path
      @variant_namespace = namespace
      @pool_size = pool_size
      @timeout = timeout
      @open_timeout = open_timeout
      @disable_cache = disable_cache
    end

    sig { params(params: Hash).returns(AssignmentResponse) }
    def get_assignment(params = {})
      body = track_execution_time("azure.exp.assignmentclient.get_assignment.duration.ms") do
        get_body(params)
      end
      AssignmentResponse.new(body)
    end

    def clear_cache(params = {})
      cache_key = assignment_cache_key(params)
      return if Feeds::KV.store.get(cache_key).value { nil }.blank?

      ActiveRecord::Base.connected_to(role: :writing) do
        Feeds::KV.store.del(cache_key)
      end
    end

    private

    attr_reader :timeout, :open_timeout

    def get_body(params)
      cache_key = assignment_cache_key(params)
      cached_body = Feeds::KV.store.get(cache_key).value { nil }

      if cache_enabled?
        if cached_body.present?
          GitHub.dogstats.increment("azure.exp.assignmentclient.get_assignment.cache_hit")
          return cached_body
        end

        GitHub.dogstats.increment("azure.exp.assignmentclient.get_assignment.cache_miss")
      end


      response = track_execution_time("azure.exp.assignmentclient.request.duration.ms", tags: ["assignment_path:#{@assignment_path}"]) do |tags|
        headers = params.empty? ? params : { "x-exp-parameters" => params_to_string(params) }
        conn.get(@assignment_path, nil, headers).tap do |res|
          tags << "success:#{res.success?}"
        end
      end

      if response.success?
        response_body = response.body

        ActiveRecord::Base.connected_to(role: :writing) do
          Feeds::KV.store.set(cache_key, response_body, expires: 12.hours.from_now)
        end

        response_body
      else
        Failbot.report(AssignmentRequestError.new(response.reason_phrase))
        nil
      end
    rescue Faraday::TimeoutError, Faraday::ConnectionFailed, Faraday::Error
      GitHub.dogstats.increment("azure.exp.assignmentclient.request.timeout")
      nil
    end

    def assignment_cache_key(params)
      cache_key = {
        "namespace": @variant_namespace,
        "clientid": params.symbolize_keys[:clientid],
        "ghstaff": params.symbolize_keys[:ghstaff]
      }.compact

      "azureexp.assignment.#{params_to_string(cache_key)}.#{@assignment_path}"
    end

    def params_to_string(params)
      params.map do |key, value|
        if [true, false].include?(value)
          value = value ? 1 : 0
        end

        "#{key}=#{value}"
      end.join(",")
    end

    def conn
      @conn ||= Faraday.new(url: EXP_URI, headers: { "User-Agent" => USER_AGENT }, request: { timeout: timeout, open_timeout: open_timeout }) do |conn|
        conn.use ::GitHub::FaradayMiddleware::Resilient, name: SERVICE_NAME, options: {
          instrumenter: GitHub,
          sleep_window_seconds: 10,
          request_volume_threshold: Rails.env.test? ? 0 : 20,
          error_threshold_percentage: Rails.env.test? ? 50 : 5,
          window_size_in_seconds: 30,
          bucket_size_in_seconds: 5,
        }
        conn.adapter Faraday.default_adapter
      end
    end

    def track_execution_time(metric_name, tags: [])
      start_time = GitHub::Dogstats.monotonic_time
      result = yield(tags)
      elapsed = GitHub::Dogstats.duration(start_time)
      GitHub.dogstats.distribution(metric_name, elapsed, tags: tags)

      result
    end

    def cache_enabled?
      !@disable_cache
    end
  end
end
