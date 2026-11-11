# typed: false
# frozen_string_literal: true

module SpokesAPI
  module Connection
    SERVICE_NAME = "spokes_api"

    class CaptureResponseHeaders < ::Faraday::Middleware
      def on_complete(env)
        SpokesAPI::Connection.response_headers = env.response_headers
      end
    end

    def self.response_headers
      @response_headers ||= {}
    end

    def self.response_headers=(headers)
      @response_headers = headers
    end

    def self.client
      @client ||= GitHub::Spokes::Proto::Client.new(connection)
    end

    def self.connection
      return @connection if @connection

      @connection ||= build_faraday_connection
    end

    def self.connection_for_streaming
      return @connection_for_streaming if @connection_for_streaming

      @connection_for_streaming ||= build_faraday_connection(
        methods: [:get, :post],
        dogstats_options: {
          enable_path_tag: false,
          custom_tags: ->(env) {
            # Replace streaming repository/blob paths which can have a high cardinality
            path = env[:url].request_uri

            if match = path.match(%r{/streaming/(v[0-9]+)/repositories/\d+/blobs/*})
              path = "/streaming/#{match[1]}/repositories/:repository_id/blobs/:oid"
            end

            ["path:#{path}"]
          }
        }
      )
    end

    def self.build_faraday_connection(methods: [:post], dogstats_options: {})
      ssl = nil

      certs = GitHub.spokesd_certs
      unless certs.nil?
        ssl = {
          ca_file: certs[0],
          client_key: certs[1],
          client_cert: certs[2],
        }
      end

      ::Faraday.new(GitHub.spokesd_url, ssl: ssl) do |conn|
        conn.options[:open_timeout] = 0.250
        conn.headers[:user_agent]   = "github-#{GitHub.role}/#{GitHub.current_sha}"

        conn.request :retry,
          max:                 3,
          interval:            0.050,
          interval_randomness: 0.5,
          backoff_factor:      1.2,

          # What methods should faraday attempt a retry?
          # In Twirp, everything is a POST...
          methods:     methods,
          exceptions:  [Faraday::ConnectionFailed, Faraday::RetriableResponse, Faraday::TimeoutError],
          retry_block: retry_proc

        conn.use ::GitHub::FaradayMiddleware::RequestID
        conn.use ::GitHub::FaradayMiddleware::Datadog, { stats: GitHub.dogstats, service_name: SERVICE_NAME, enable_path_tag: true }.merge(dogstats_options)
        conn.use ::GitHub::FaradayMiddleware::Resilient, name: SERVICE_NAME
        conn.use ::GitHub::FaradayMiddleware::IncreasingTimeout,
          factor: 2
        if vexi_enabled?(:spokesd_request_timeout_header_spokes_api)
          # Add a fudge factor of 150ms as to allow spokesd to detect the timeout before the
          # client times out and disconnects.
          conn.use GitHub::FaradayMiddleware::RequestTimeoutHeader, fudge_factor: 0.150
        end
        conn.use ::GitHub::DataCollector::SpokesdInstrumenterCollector::FaradayMiddleware

        conn.use ::SpokesAPI::Connection::CaptureResponseHeaders
        conn.adapter :typhoeus
      end
    end

    def self.retry_proc
      proc do |env, _, _retries, exception|
        tags = [
          "status:#{env[:status]}",
          "method:#{env[:method]}",
          "path:#{env[:url].request_uri}",
          "error:#{exception.class}",
        ]
        GitHub.dogstats.increment("rpc.#{SERVICE_NAME}.retries", tags: tags)
      end
    end

    def self.vexi_enabled?(feature_flag)
      defined?(FeatureFlag) && FeatureFlag.respond_to?(:vexi) && FeatureFlag.vexi.enabled?(feature_flag, default: false)
    end
  end
end
