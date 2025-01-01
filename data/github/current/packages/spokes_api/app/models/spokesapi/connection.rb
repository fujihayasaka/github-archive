# typed: false
# frozen_string_literal: true

module SpokesAPI
  module Connection
    SERVICE_NAME = "spokes_api"

    def self.client
      @client ||= GitHub::Spokes::Proto::Client.new(connection)
    end

    def self.connection
      raise Disabled unless GitHub.spokesd_enabled?
      return @connection if @connection

      ssl = nil

      certs = GitHub.spokesd_certs
      unless certs.nil?
        ssl = {
          ca_file: certs[0],
          client_key: certs[1],
          client_cert: certs[2],
        }
      end

      @connection ||= ::Faraday.new(GitHub.spokesd_url, ssl: ssl) do |conn|
        conn.options[:open_timeout] = 0.250
        conn.headers[:user_agent]   = "github-#{GitHub.role}/#{GitHub.current_sha}"

        conn.request :retry,
          max:                 3,
          interval:            0.050,
          interval_randomness: 0.5,
          backoff_factor:      1.2,

          # What methods should faraday attempt a retry?
          # In Twirp, everything is a POST...
          methods:     [:post],
          exceptions:  [Faraday::ConnectionFailed, Faraday::RetriableResponse, Faraday::TimeoutError],
          retry_block: retry_proc

        conn.use ::GitHub::FaradayMiddleware::RequestID
        conn.use ::GitHub::FaradayMiddleware::Datadog, stats: GitHub.dogstats, service_name: SERVICE_NAME, enable_path_tag: true
        conn.use ::GitHub::FaradayMiddleware::Resilient, name: SERVICE_NAME
        conn.use ::GitHub::FaradayMiddleware::IncreasingTimeout,
          factor: 2
        if GitHub.respond_to?(:flipper) && GitHub.flipper[:spokesd_request_timeout_header_spokes_api].enabled?
          # Add a fudge factor of 150ms as to allow spokesd to detect the timeout before the
          # client times out and disconnects.
          conn.use GitHub::FaradayMiddleware::RequestTimeoutHeader, fudge_factor: 0.150
        end

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
  end
end
