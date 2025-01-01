# typed: true
#frozen_string_literal: true

module Audit
  module HttpFluentbit
    class Logger
      attr_accessor :server
      attr_accessor :path
      attr_writer :connection

      class ResponseError < StandardError; end

      RETRY_STATUSES = [429, 502, 503, 504]

      def initialize(server)
        @server = server
      end

      def perform(payload)
        return unless GitHub.http_fluentbit_enabled?

        response = connection.post do |req|
          req.url @path
          req.headers["Content-Type"] = "application/json"
          req.body = { log_message: split_payload!(payload).to_json, log_type: "github_audit" }.to_json
        end

        unless response.success?
          GitHub.dogstats.increment("audit.entry.error", tags: dogtags)

          err = ResponseError.new("Error response from log forwarder")
          Failbot.report(
            err,
            message: response.body
          )

          # We want to raise the error here so that the `LogAuditEntryJob` can catch it and retry
          # These are errors and data that we *do not* want to lose so it's a second catch for these errors
          # to make sure they are continuously retried
          if RETRY_STATUSES.include?(response.status)
            GitHub.dogstats.increment("audit.entry.retry", tags: dogtags)
            raise err
          end
        end

        GitHub.dogstats.increment("audit.entry.indexing.success", tags: dogtags)
        response
      end

      def connection
        uri = URI::parse(@server)

        uri.host = uri.host
        uri.port = uri.port
        uri.scheme = uri.scheme
        uri.path = uri.path

        @path = uri.path

        url = "#{uri.scheme}://#{uri.host}:#{uri.port}"

        @connection ||= Faraday.new(url: url) do |c|
          c.request :retry, retry_options
          c.adapter Faraday.default_adapter
        end
      end

      # Internal: Sets the tags for datadog stats
      #
      # returns an array of tag:value
      def dogtags
        ["destination:fluentbit"]
      end

      # Splits non-indexed Audit payload data into a separate 'data'
      # key.
      #
      #   split_payload(:actor_id => 1, :foo => 'bar')
      #   # {:actor_id => 1, :data => {:foo => 'bar'}}
      #
      # Returns a Hash.
      def split_payload!(payload)
        data = {}
        payload.each_key do |key|
          next if HTTP_FLUENTBIT_EVENT_ITEMS.include?(key.to_sym)
          data[key] = payload.delete(key)
        end
        payload[:data] = data
        payload
      end

      def retry_options
        {
          max: 10,
          interval: 0.05,
          interval_randomness: 0.5,
          backoff_factor: 2,
          retry_statuses: RETRY_STATUSES,
          methods: [:post], #default methods list does not include POST
        }
      end
    end
  end
end
