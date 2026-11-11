# typed: strict
# frozen_string_literal: true

module ApiInsights::Stats
  class KustoClientProvider
    include Singleton

    EMPTY_QUERY_PARAMETERS = T.let({}, T::Hash[String, T.untyped])

    MAX_AUTH_RETRIES = 2
    AUTH_COOLDOWN_SECONDS = 30
    BASE_RETRY_DELAY_SECONDS = 0.1
    RETRY_JITTER_MIN = 0.5
    RETRY_JITTER_MAX = 1.5
    MAX_ERROR_DETAILS_LENGTH = 2000
    REDACTED_VALUE = "[REDACTED]"

    KUSTO_QUERY_METRIC = "api_insights.kusto.query"
    KUSTO_QUERY_DURATION_METRIC = "api_insights.kusto.query.duration_ms"
    KUSTO_AUTH_FAILURE_METRIC = "api_insights.kusto.auth_token.failure"
    KUSTO_AUTH_RETRY_METRIC = "api_insights.kusto.auth_token.retry"
    KUSTO_CLIENT_REFRESH_METRIC = "api_insights.kusto.client.refresh"
    KUSTO_AUTH_COOLDOWN_METRIC = "api_insights.kusto.auth_token.cooldown"
    CODE_NAMESPACE = "ApiInsights::Stats::KustoClientProvider"
    SENSITIVE_ERROR_DETAIL_KEY_FRAGMENTS = T.let(
      %w[token access_token refresh_token secret client_secret assertion password authorization],
      T::Array[String],
    )

    sig { returns(Kusto::Data::Client) }
    def self.kusto_client
      self.instance.kusto_client
    end

    sig do
      params(
        database: String,
        query_text: String,
        parameters: T::Hash[String, T.untyped],
        source: String,
      ).returns(Kusto::Data::Dataset)
    end
    def self.query(database, query_text, parameters = EMPTY_QUERY_PARAMETERS, source: "unknown")
      self.instance.query(database, query_text, parameters, source: source)
    end

    sig { returns(Kusto::Data::Client) }
    def kusto_client
      @kusto_client
    end

    sig do
      params(
        database: String,
        query_text: String,
        parameters: T::Hash[String, T.untyped],
        source: String,
      ).returns(Kusto::Data::Dataset)
    end
    def query(database, query_text, parameters = EMPTY_QUERY_PARAMETERS, source: "unknown")
      start_time = Time.now.utc
      attempt = 0
      auth_failure_seen = false

      begin
        attempt += 1
        block_reason = auth_cooldown_block_reason(now: monotonic_now)
        if block_reason
          GitHub.dogstats.increment(
            KUSTO_AUTH_COOLDOWN_METRIC,
            tags: ["source:#{source}", "attempt:#{attempt}"],
          )
          GitHub.logger.warn("api insights kusto auth request blocked by cooldown", {
            "code.namespace" => CODE_NAMESPACE,
            "kusto.source" => source,
            "kusto.database" => database,
            "kusto.attempt" => attempt,
            "kusto.cooldown_remaining_seconds" => block_reason,
          })
          raise Kusto::UnauthorizedError, "Kusto auth cooldown is active"
        end

        dataset = kusto_client.query(database, query_text, parameters)

        tags = [
          "source:#{source}",
          "success:true",
          "attempts:#{attempt}",
          "auth_failure_seen:#{auth_failure_seen}",
        ]
        GitHub.dogstats.increment(KUSTO_QUERY_METRIC, tags: tags)
        dataset
      rescue Kusto::Error => e
        auth_failure = auth_token_failure?(e)
        cooldown_error = auth_cooldown_error?(e)
        if auth_failure
          auth_failure_seen = true
          retrying = attempt <= MAX_AUTH_RETRIES && !cooldown_error
          log_auth_failure(
            source: source,
            database: database,
            attempt: attempt,
            error: e,
            retrying: retrying,
          )
          GitHub.dogstats.increment(
            KUSTO_AUTH_FAILURE_METRIC,
            tags: ["source:#{source}", "error:#{e.class.name}", "attempt:#{attempt}"],
          )
        end

        if auth_failure && !cooldown_error && attempt <= MAX_AUTH_RETRIES
          GitHub.dogstats.increment(KUSTO_AUTH_RETRY_METRIC, tags: ["source:#{source}", "attempt:#{attempt}"])
          sleep_for_retry(source: source, database: database, attempt: attempt)
          refresh_kusto_client!(source: source)
          retry
        end

        open_auth_cooldown! if auth_failure && !cooldown_error

        GitHub.dogstats.increment(
          KUSTO_QUERY_METRIC,
          tags: ["source:#{source}", "success:false", "error:#{e.class.name}", "attempts:#{attempt}", "auth_failure_seen:#{auth_failure_seen}"],
        )
        log_query_failure(source: source, database: database, attempt: attempt, auth_failure_seen: auth_failure_seen, error: e)
        raise
      ensure
        GitHub.dogstats.timing(
          KUSTO_QUERY_DURATION_METRIC,
          GitHub::Dogstats.duration(start_time),
          tags: ["source:#{source}", "attempts:#{attempt}", "auth_failure_seen:#{auth_failure_seen}"],
        )
      end
    end

    private

    sig { void }
    def initialize
      @kusto_client_mutex = T.let(Mutex.new, Mutex)
      @auth_cooldown_until = T.let(nil, T.nilable(Float))
      @kusto_client = T.let(build_kusto_client, Kusto::Data::Client)
    end

    sig { returns(Kusto::Data::Client) }
    def build_kusto_client
      builder = Kusto::Data::ClientBuilder.new
      if GitHub.api_insights_use_local_kusto
        builder.use_local_cluster(port: 42000)
      else
        builder
          .use_azure_cluster(GitHub.api_insights_kusto_cluster_name)
          .use_app_auth(
            GitHub.api_insights_gh_azure_tenant_id,
            GitHub.api_insights_sp_client_id,
            GitHub.api_insights_sp_client_secret)
      end
      builder.build
    end

    sig { params(source: String).void }
    def refresh_kusto_client!(source:)
      @kusto_client_mutex.synchronize do
        @kusto_client = build_kusto_client
      end
      GitHub.dogstats.increment(KUSTO_CLIENT_REFRESH_METRIC, tags: ["source:#{source}"])
    end

    sig { params(error: Kusto::Error).returns(T::Boolean) }
    def auth_token_failure?(error)
      error.message.include?("acquiring an access token")
    end

    sig { params(error: Kusto::Error).returns(T::Boolean) }
    def auth_cooldown_error?(error)
      error.is_a?(Kusto::UnauthorizedError) && error.message.include?("cooldown")
    end

    sig { params(source: String, database: String, attempt: Integer).void }
    def sleep_for_retry(source:, database:, attempt:)
      delay_seconds = retry_delay_seconds(attempt)
      GitHub.logger.info("api insights kusto auth retry backoff", {
        "code.namespace" => CODE_NAMESPACE,
        "kusto.source" => source,
        "kusto.database" => database,
        "kusto.attempt" => attempt,
        "kusto.retry_delay_ms" => (delay_seconds * 1000).round,
      })
      sleep(delay_seconds)
    end

    sig { params(attempt: Integer).returns(Float) }
    def retry_delay_seconds(attempt)
      base_delay = BASE_RETRY_DELAY_SECONDS * (2**(attempt - 1))
      jitter = rand(RETRY_JITTER_MIN..RETRY_JITTER_MAX)
      (base_delay * jitter).to_f
    end

    sig { returns(Float) }
    def monotonic_now
      T.cast(Process.clock_gettime(Process::CLOCK_MONOTONIC), Float)
    end

    sig { params(now: Float).returns(T.nilable(Float)) }
    def auth_cooldown_block_reason(now:)
      @kusto_client_mutex.synchronize do
        return nil unless @auth_cooldown_until
        remaining = @auth_cooldown_until - now
        if remaining <= 0
          @auth_cooldown_until = nil
          return nil
        end

        remaining.round(2).to_f
      end
    end

    sig { void }
    def open_auth_cooldown!
      @kusto_client_mutex.synchronize do
        @auth_cooldown_until = monotonic_now + AUTH_COOLDOWN_SECONDS.to_f
      end
    end

    sig do
      params(
        source: String,
        database: String,
        attempt: Integer,
        error: Kusto::Error,
        retrying: T::Boolean,
      ).void
    end
    def log_auth_failure(source:, database:, attempt:, error:, retrying:)
      payload = T.let({
        "code.namespace" => CODE_NAMESPACE,
        "kusto.source" => source,
        "kusto.database" => database,
        "kusto.attempt" => attempt,
        "kusto.max_auth_retries" => MAX_AUTH_RETRIES,
        "kusto.retrying" => retrying,
        "error.class" => error.class.name,
        "error.message" => error.message,
      }, T::Hash[String, T.untyped])
      details = serialized_error_details(error)
      payload["error.details"] = details if details

      GitHub.logger.warn("api insights kusto auth token acquisition failed", payload)
    end

    sig do
      params(
        source: String,
        database: String,
        attempt: Integer,
        auth_failure_seen: T::Boolean,
        error: Kusto::Error,
      ).void
    end
    def log_query_failure(source:, database:, attempt:, auth_failure_seen:, error:)
      payload = T.let({
        "code.namespace" => CODE_NAMESPACE,
        "kusto.source" => source,
        "kusto.database" => database,
        "kusto.attempt" => attempt,
        "kusto.auth_failure_seen" => auth_failure_seen,
        "error.class" => error.class.name,
        "error.message" => error.message,
      }, T::Hash[String, T.untyped])
      details = serialized_error_details(error)
      payload["error.details"] = details if details

      GitHub.logger.error("api insights kusto query failed", payload)
    end

    sig { params(error: Kusto::Error).returns(T.nilable(String)) }
    def serialized_error_details(error)
      return nil unless T.unsafe(error).respond_to?(:details)

      details = T.unsafe(error).details
      return nil if details.nil?

      serialized = sanitize_error_details(details).inspect
      return serialized if serialized.length <= MAX_ERROR_DETAILS_LENGTH

      "#{serialized[0...MAX_ERROR_DETAILS_LENGTH]}...[truncated]"
    rescue StandardError
      nil
    end

    sig { params(value: T.untyped).returns(T.untyped) }
    def sanitize_error_details(value)
      if value.is_a?(Hash)
        value.each_with_object({}) do |(key, nested_value), sanitized|
          key_str = key.to_s
          sanitized[key_str] = sensitive_error_detail_key?(key_str) ? REDACTED_VALUE : sanitize_error_details(nested_value)
        end
      elsif value.is_a?(Array)
        value.map { |nested_value| sanitize_error_details(nested_value) }
      else
        value
      end
    end

    sig { params(key: String).returns(T::Boolean) }
    def sensitive_error_detail_key?(key)
      downcased = key.downcase
      SENSITIVE_ERROR_DETAIL_KEY_FRAGMENTS.any? { |fragment| downcased.include?(fragment) }
    end
  end
end
