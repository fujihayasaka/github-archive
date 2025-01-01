# typed: true
# frozen_string_literal: true

module ActionsMetrics
  class Client

    SERVICE_NAME = "actions-usage-metrics".freeze

    sig { returns(ActionsUsageMetrics::Client) }
    attr_reader :client

    sig { returns(T.nilable(String)) }
    attr_reader :host


    sig { params(biz: T.untyped, org: T.untyped, user: T.untyped).void }
    def initialize(biz: nil, org: nil, user: nil)
      # lab dotcom traffic should fallback to prod endpoint for service
      lab_fallback_to_prod = user&.feature_flag_enabled?(:actions_usage_metrics_lab_fallback_to_prod, default: false)

      # prod dotcom traffic should fallback to lab endpoint for service
      prod_fallback_to_lab = user&.feature_flag_enabled?(:actions_usage_metrics_prod_fallback_to_lab, default: false)

      if inferred_env == :production
        # 33435682 = bbq-beets, 125400886 = bbq-beets-four-nines
        org_is_lab = org != nil && %w[bbq-beets bbq-beets-four-nines].include?(org&.name) && (org&.id == 33435682 || org&.id == 125400886)
        biz_is_lab = biz != nil && %w[avocado-corp].include?(biz&.display_login) && biz&.id == 2 # avocado-corp

        if org_is_lab || biz_is_lab
          set_lab

          if lab_fallback_to_prod
            set_production
          end
        else
          set_production

          if prod_fallback_to_lab
            set_lab
          end
        end
      else
        set_dev
      end

      @client = platform_client
    end

    def default_host_mapping
      {
        development: "http://aum.local:32474",
        lab: "https://actions-usage-metrics-lab.service.iad.github.net",
        production: GitHub.actions_usage_metrics_host,
      }
    end

    private

    sig { returns(ActionsUsageMetrics::Client) }
    def platform_client
      ActionsUsageMetrics::Client.new(host: @host, hmac_key: @hmac_key) do |conn|
        conn.request :retry, retry_options
        conn.use GitHub::FaradayMiddleware::RequestID
        conn.use GitHub::FaradayMiddleware::Datadog, stats: GitHub.dogstats, service_name: SERVICE_NAME
      end
    end

    def inferred_env
      env_value = ENV["HEAVEN_DEPLOYED_ENV"] || ENV["STAFF_ENVIRONMENT"]
      if !env_value.nil?
        return :production # always return production unless this is dev since prod/lab/review-lab are all treated the same
      end

      :development
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

    def set_production
      @host = default_host_mapping[:production]
      @hmac_key = GitHub.actions_usage_metrics_production_hmac_key
    end

    def set_lab
      @host = default_host_mapping[:lab]
      @hmac_key = GitHub.actions_usage_metrics_lab_hmac_key
    end

    def set_dev
      @host = default_host_mapping[:development]
      @hmac_key = GitHub.actions_usage_metrics_production_hmac_key
    end
  end
end
