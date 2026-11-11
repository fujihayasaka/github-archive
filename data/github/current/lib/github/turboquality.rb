# typed: true
# frozen_string_literal: true

require "turboquality"
require "github/faraday_adapter/persistent_excon"
require "github/turboquality_uploader"

module GitHub
  class Turboquality
    SERVICE_NAME = "turboquality"
    FAILBOT_APP_NAME = "github-turboquality-client"

    class ResponseError < StandardError
      attr_reader :error
      def initialize(error)
        @error = error
        super(error)
      end
    end

    sig do
      type_parameters(:U).
      params(response: Twirp::ClientResp[T.type_parameter(:U)]).
      returns(T.type_parameter(:U))
    end
    def self.check_error(response)
      error = response.error
      unless error.nil?
        e = ::GitHub::Turboquality::ResponseError.new(error.msg)
        Failbot.report(e, catalog_service: "github/code_scanning")
        raise e
      end
      response.data
    end

    def self.content_type
      return "application/json" if Rails.env.test? # rubocop:disable GitHub/DoNotBranchOnRailsEnv
      "application/protobuf"
    end

    sig { returns(::Turboquality::Proto::CodeQualityAPIClient) }
    def self.client
      @client ||= ::Turboquality::Proto::CodeQualityAPIClient.new(::GitHub::Turboquality.connection, { content_type: content_type })
    end

    def self.async_client
      @async_client ||= ::Turboquality::Proto::CodeQualityAPIClient.new(::GitHub::Turboquality.connection(async: true), { content_type: content_type })
    end

    def self.connection(async: false, timeout: 5, open_timeout: 1)
      (async ? ConcurrentFaraday : GitHub::FaradayClient::Internal).new(url: GitHub.turboquality_url) do |conn|
        conn.use GitHub::FaradayMiddleware::Staffbar, url: GitHub.turboquality_url
        conn.use GitHub::FaradayMiddleware::HMACAuth, hmac_key: GitHub.turboquality_hmac_key
        conn.use GitHub::FaradayMiddleware::RequestID
        conn.use GitHub::FaradayMiddleware::TenantContext
        conn.use (async ? ::GitHub::FaradayMiddleware::DatadogAsync : ::GitHub::FaradayMiddleware::Datadog),
          stats: GitHub.dogstats,
          service_name: "Turboquality",
          catalog_service: "github/code_scanning",
          enable_path_tag: true

        conn.request :retry,
          max:                 3,
          interval:            0.050,
          interval_randomness: 0.5,
          backoff_factor:      1.2,
          retry_statuses: [429, 502, 503, 504],
          # In Twirp, everything is a POST
          methods:     [:post],
          exceptions:  [Faraday::ConnectionFailed, Faraday::RetriableResponse, Faraday::TimeoutError, Faraday::ServerError],
          retry_block: retry_block(timeout: timeout)

        conn.use GitHub::FaradayMiddleware::Resilient, name: "Turboquality:CodeQualityAPI", options: {
          instrumenter: GitHub,
          sleep_window_seconds: 5,
          error_threshold_percentage: 50,
          window_size_in_seconds: 30,
          bucket_size_in_seconds: 5,
        }
        conn.use ::GitHub::FaradayMiddleware::IncreasingTimeout, factor: 2
        conn.options[:open_timeout] = open_timeout # seconds
        conn.options[:timeout] = timeout # seconds
        conn.adapter :persistent_excon
      end
    end

    def self.retry_block(timeout:)
      proc do |env, _, _, exception|
        # use monotonic clock when calculating elapsed time to account for clock changes
        env[:retry_started_at] ||= Process.clock_gettime(Process::CLOCK_MONOTONIC)
        now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        raise StandardError.new("request timed out") if now - env[:retry_started_at] >= timeout

        tags = [
          "status:#{env[:status]}",
          "method:#{env[:method]}",
          "path:#{env[:url].request_uri}",
          "error:#{exception.class}",
        ]
        GitHub.dogstats.increment("rpc.#{SERVICE_NAME}.retries", tags: tags)
      end
    end

    sig { returns(::GitHub::TurboqualityUploader) }
    def self.uploader
      @uploader ||= TurboqualityUploader.new
    end

    sig { params(repo_id: Integer, params: T::Hash[Symbol, T.untyped], sarif: T.nilable(Turboscan::ValidatedAnalysis)).returns(T.nilable(T::Hash[Symbol, String])) }
    def self.upload_analysis(repo_id, params, sarif)
      uploader.upload_analysis(repo_id, params, sarif)
    end

    sig { params(rule_category: String).returns(T.nilable(Integer)) }
    def self.to_rule_category(rule_category)
      rule_category = rule_category.upcase.prepend("CAT_").to_sym
      ::Turboquality::Proto::RuleCategory.resolve(rule_category)
    end

    sig { params(rule_severity: String).returns(T.nilable(Integer)) }
    def self.to_rule_severity(rule_severity)
      rule_severity = rule_severity.upcase.prepend("SEV_").to_sym
      ::Turboquality::Proto::RuleSeverity.resolve(rule_severity)
    end

    sig { params(rule_language: String).returns(T.nilable(Integer)) }
    def self.to_rule_language(rule_language)
      rule_language = rule_language.upcase.prepend("RULE_LANGUAGE_").to_sym
      ::Turboquality::Proto::RuleLanguage.resolve(rule_language)
    end

    sig { params(state: String).returns(T.nilable(Integer)) }
    def self.to_dismissal_state(state)
      state = state.upcase.prepend("DISMISSAL_STATE_").to_sym
      ::Turboquality::Proto::DismissalState.resolve(state)
    end
  end
end
