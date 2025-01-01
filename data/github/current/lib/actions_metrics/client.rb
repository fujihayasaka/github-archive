# typed: true
# frozen_string_literal: true

module ActionsMetrics
  class Client
    extend T::Sig

    SERVICE_NAME = "actions-usage-metrics".freeze

    sig { returns(T.nilable(Integer)) }
    attr_reader :timeout

    sig { returns(ActionsUsageMetrics::Client) }
    attr_reader :client

    sig { params(org: T.nilable(String), timeout: T.nilable(Integer), host: T.nilable(String)).void }
    def initialize(org: nil, timeout: nil, host: nil)

      if inferred_env == :production || inferred_env == :review_lab || inferred_env == :lab
        if %w[bbq-beets bbq-beets-four-nines].include?(org)
          @host = default_host_mapping[:lab]
          @hmac_key = GitHub.actions_usage_metrics_lab_hmac_key
        else
          @host = default_host_mapping[:production]
          @hmac_key = GitHub.actions_usage_metrics_production_hmac_key
        end
      else
        @host = default_host_mapping[:development]
        @hmac_key = GitHub.actions_usage_metrics_production_hmac_key
      end

      @timeout = timeout
      @client = platform_client
    end

    private

    sig { returns(ActionsUsageMetrics::Client) }
    def platform_client
      ActionsUsageMetrics::Client.new(host: @host, hmac_key: @hmac_key) do |conn|
        conn.options.timeout = timeout if !timeout.nil?
        conn.request :retry, retry_options
        conn.use GitHub::FaradayMiddleware::RequestID
        conn.use GitHub::FaradayMiddleware::Datadog, stats: GitHub.dogstats, service_name: SERVICE_NAME
      end
    end

    def inferred_env
      env_value = ENV["HEAVEN_DEPLOYED_ENV"]
      if !env_value.nil?
        return :production if env_value.match?(/\A(?:production|prod)\b/)
        return :lab if env_value.match?(/\lab\b/)
      end
      env_value = ENV["STAFF_ENVIRONMENT"]
      if !env_value.nil?
        return :review_lab if env_value == "review-lab"
      end
      env_value = ENV.fetch("RACK_ENV", "development")
      env_value.to_sym
    end

    def default_host_mapping
      {
        development: "http://localhost:34474",
        lab: "https://actions-usage-metrics-lab.service.iad.github.net",
        production: "https://actions-usage-metrics-production.service.iad.github.net",
      }
    end

    def retry_options
      {
        max: 2,
        interval: 0.050,
        interval_randomness: 0.5,
        backoff_factor: 1.2,
        methods: [:post],
        exceptions: [Faraday::ConnectionFailed],
        retry_block: retry_proc,
      }
    end

    def retry_proc
      proc do |env, _, retries, exception|
        tags = [
          "status:#{env[:status]}",
          "retries:#{retries}",
          "rpc:#{env[:url].request_uri.sub('/twirp/', '')}",
          "error:#{exception.class}",
        ]
        GitHub.dogstats.increment("actions-usage-metrics.client.retry", tags: tags)
      end
    end
  end
end
