# typed: strict
# frozen_string_literal: true

require "licensify/client"

module Licensing
  module Licensify
    extend T::Sig

    SERVICE_NAME = T.let("licensify", String)

    sig { params(timeout: T.nilable(Integer)).returns(::Licensify::Client) }
    def licensify_client(timeout: nil)
      @licensify_client ||= T.let(build_client(timeout: timeout), T.nilable(::Licensify::Client))
    end

    private

    sig { params(timeout: T.nilable(Integer)).returns(::Licensify::Client) }
    def build_client(timeout: nil)
      ::Licensify::Client.new(host: GitHub.licensify_host, hmac_key: GitHub.licensify_hmac_key) do |conn|
        conn.options.timeout = timeout if !timeout.nil?
        conn.request :retry, {
          max: 2,
          interval: 0.050,
          interval_randomness: 0.5,
          backoff_factor: 1.2,
          methods: [:post],
          exceptions: [Faraday::ConnectionFailed],
          retry_block: -> (env, _, retries, exception) {
            tags = [
              "status:#{env[:status]}",
              "retries:#{retries}",
              "error:#{exception.class}",
              "path:#{env[:url].request_uri}"
            ]
            GitHub.dogstats.increment("licensify_client.retries", tags: tags)
          }
        }
        conn.use GitHub::FaradayMiddleware::RequestID
        conn.use GitHub::FaradayMiddleware::TenantContext
        conn.use GitHub::FaradayMiddleware::Datadog, stats: GitHub.dogstats, service_name: SERVICE_NAME, enable_path_tag: true
      end
    end
  end
  extend ::Licensing::Licensify
end
