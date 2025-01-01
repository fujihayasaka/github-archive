# typed: true
# frozen_string_literal: true

module TimelineApiClient
  SERVICE_NAME = "timelined".freeze
  TIMEOUT_PROD = 0.4.freeze
  TIMEOUT_OTHER = 2.freeze
  TIMEOUT_LOCAL = 10.freeze

  RETRY_OPTIONS = {
    client_name: SERVICE_NAME,
    retry_statuses: [500, 503],
    methods: [:post],
    exceptions: [
      Errno::ETIMEDOUT,
      "Timeout::Error",
      Faraday::TimeoutError,
      Faraday::ConnectionFailed,
      Faraday::RetriableResponse,
    ]
  }


  def self.determine_timeout
    if GitHub.heaven_env == "production"
      TIMEOUT_PROD
    elsif Rails.env.development?
      TIMEOUT_LOCAL
    else
      TIMEOUT_OTHER
    end
  end

  def self.api_endpoint
    GitHub.timelined_api_url
  end

  def self.hmac_key
    GitHub.timelined_hmac_key
  end

  def self.factory_client
    timeout = determine_timeout

    @factory_client ||= begin
      conn = GitHub::FaradayClient.internal(SERVICE_NAME, api_endpoint, {
        request: {
          timeout: timeout
        }
      }) do |conn|
        conn.use GitHub::FaradayMiddleware::Retries, RETRY_OPTIONS
        conn.use GitHub::FaradayMiddleware::Datadog, enable_path_tag: true
        # Note: Resilient options not explicitly set here will default
        # to the values specified in GitHub::FaradayClient::DEFAULT_RESILIENT_OPTIONS.
        # See https://github.com/github/github/blob/master/lib/github/faraday_client.rb#L36-L43
        conn.use GitHub::FaradayMiddleware::Resilient, options: {
          # Seconds after tripping circuit before allowing retry
          sleep_window_seconds: 5,

          # Number of seconds in the statistical window
          window_size_in_seconds: 60,

          # Size of buckets in statistical window
          bucket_size_in_seconds: 10,
        }
      end

      ::Timeline::Client.new(conn, hmac_key)
    end
  end

  def self.async_client
    @async_client ||= begin
      conn = ::ConcurrentFaraday.new(api_endpoint) do |conn|
        configure_timeline_api_connection_options(conn)
        conn.use GitHub::FaradayMiddleware::DatadogAsync,
          stats: GitHub.dogstats,
          service_name: SERVICE_NAME,
          enable_path_tag: true
        conn.adapter :concurrent_adapter, persistent: true
      end

      ::Timeline::Client.new(conn, hmac_key)
    end
  end

  def self.configure_timeline_api_connection_options(conn)
    conn.options[:open_timeout] = 1 # seconds
    conn.options[:timeout] = 0.5 # seconds

    conn.use GitHub::FaradayMiddleware::RequestID
    conn.use GitHub::FaradayMiddleware::Resilient, name: SERVICE_NAME, options: {
      instrumenter: GitHub,

      # Seconds after tripping circuit before allowing retry
      sleep_window_seconds: 5,

      # % of "marks" that must be failed to trip the circuit
      error_threshold_percentage: 25,

      # Number of seconds in the statistical window
      window_size_in_seconds: 60,

      # Size of buckets in statistical window
      bucket_size_in_seconds: 10,
    }
  end
end
