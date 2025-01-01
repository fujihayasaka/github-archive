# typed: true
# frozen_string_literal: true

module GitHub
  class TurboscanConnection
    SERVICE_NAME = "turboscan"
    READ_TIMEOUT = 5.0 # seconds

    def self.new_connection(twirp_service:)
      resilient_middleware_params = {}
      # For ManagedAnalyses we want to be less sensitive to errors
      if twirp_service == "ManagedAnalyses"
        resilient_middleware_params[:sleep_window_seconds] = 5
        resilient_middleware_params[:error_threshold_percentage] = 50
      end

      connection(
        connection_module: GitHub::FaradayClient::Internal,
        datadog_class: GitHub::FaradayMiddleware::Datadog,
        additional_datadog_tags: ["twirp_service:#{twirp_service}", "concurrent:false"],
        resilient_middleware_name: "#{TurboscanConnection::SERVICE_NAME}:#{twirp_service}",
        **resilient_middleware_params
      ) do |conn|
        conn.adapter :persistent_excon
      end
    end

    def self.async_connection(twirp_service:)
      connection(
        connection_module: ConcurrentFaraday,
        datadog_class: GitHub::FaradayMiddleware::DatadogAsync,
        additional_datadog_tags: ["twirp_service:#{twirp_service}", "concurrent:true"],
        resilient_middleware_name: "#{TurboscanConnection::SERVICE_NAME}:#{twirp_service}"
      ) do |conn|
        # These are set by default in the non-async connection class
        # but we need to explicitly set them for this one.
        conn.use GitHub::FaradayMiddleware::RequestID
        conn.use GitHub::FaradayMiddleware::TenantContext

        conn.adapter :concurrent_adapter, persistent: true
      end
    end

    # The patient_connection supports a longer timeout than the standard client.
    def self.patient_connection(twirp_service:)
      connection = new_connection(twirp_service:)

      # using the ruby method "c = connection.dup" or ".clone" here is a dangerous move because there is no guarantee that c.options hash is duped with .dup. It's better to be explicit here to make sure that the options hash is mutated.
      connection.options[:timeout] = GitHub::TurboscanConnection::READ_TIMEOUT * 2

      connection
    end

    sig do
      params(
        connection_module: T.any(T.class_of(ConcurrentFaraday), T.class_of(GitHub::FaradayClient::Internal)),
        datadog_class: T.class_of(Faraday::Middleware),
        additional_datadog_tags: T::Array[String],
        resilient_middleware_name: String,
        sleep_window_seconds: Integer,
        error_threshold_percentage: Integer,
      ).returns(::Faraday::Connection)
    end
    def self.connection(
      connection_module:,
      datadog_class:,
      additional_datadog_tags: [],
      resilient_middleware_name: TurboscanConnection::SERVICE_NAME,
      sleep_window_seconds: 10,
      error_threshold_percentage: 60
    )
      conn = connection_module.new(url: GitHub.turboscan_url) do |conn|
        conn.use GitHub::FaradayMiddleware::HMACAuth, hmac_key: GitHub.turboscan_hmac_key
        conn.use datadog_class,
          stats: GitHub.dogstats,
          service_name: TurboscanConnection::SERVICE_NAME,
          catalog_service: "github/code_scanning",
          custom_tags: additional_datadog_tags,
          tracked_availability_slos: ["turboscan"],
          enable_path_tag: true

        conn.use GitHub::FaradayMiddleware::Staffbar, url: GitHub.turboscan_url
        # We don't enable circuit breakers during tests to fix many flakes introduced by https://github.com/github/github/pull/292666.
        unless Rails.env.test? # rubocop:disable GitHub/DoNotBranchOnRailsEnv
          conn.use GitHub::FaradayMiddleware::Resilient, name: resilient_middleware_name, options: {
            instrumenter: GitHub,
            sleep_window_seconds: sleep_window_seconds,
            error_threshold_percentage: error_threshold_percentage,
            request_volume_threshold: 2,
            window_size_in_seconds: 30,
            bucket_size_in_seconds: 5,
          }
        end
        conn.options[:open_timeout] = 0.1 # connection open timeout in seconds.
        conn.options[:timeout] = TurboscanConnection::READ_TIMEOUT
      end

      yield(conn) if block_given?
      conn
    end
    private_class_method :connection
  end
end
