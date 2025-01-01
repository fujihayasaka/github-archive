# typed: true
# frozen_string_literal: true

require "connection_info"

module GitHub
  module FaradayMiddleware
    # Faraday Middleware for exposing timings from external servcies in
    # the staffbar
    class Staffbar < Faraday::Middleware
      GITHUB_INCLUDE_TIMINGS_HEADER = "X-GitHub-Staffbar-Include-Timings"
      GITHUB_TIMINGS_HEADER = "X-GitHub-Staffbar-Timings"

      attr_reader :url

      def initialize(app, options = {})
        super(app)
        @url = options[:url]
      end

      def call(env)
        if GitHub::MysqlInstrumenter.tracking?
          env.request_headers[GITHUB_INCLUDE_TIMINGS_HEADER] = "1"
        end

        @app.call(env).on_complete do |env|
          track_queries(env.response_headers[GITHUB_TIMINGS_HEADER])
        end
      end

      private

      def track_queries(payload)
        payload = decode_payload(payload)
        queries = Array(payload[:queries])

        return unless queries.present?

        start = T.let(Time.now, T.untyped)
        queries.each do |timing|
          finish = Time.at(start.to_f + (timing[:duration] / 1_000_000_000.0))
          result_count = [timing[:results], 0].max # Unsure why we max here. Was this meant to be `||` ?
          payload = {
            sql: timing[:query],
            connection: FakeConnection.new(url, timing[:type])
          }
          GitHub::MysqlInstrumenter.track_query(
            start, finish, payload,
            result_count: result_count,
            should_record_stats: false
          )
          start = finish
        end
      end

      def decode_payload(payload)
        return {} unless payload.present?

        begin
          payload = Base64.strict_decode64(payload)
        rescue ArgumentError
          return {}
        end

        return {} unless payload.present?

        begin
          GitHub::JSON.decode(payload).with_indifferent_access
        rescue Yajl::ParseError
          {}
        end
      end

      class FakeConnection
        def initialize(url, type)
          @url = url
          @type = type
        end

        def write_query?(sql)
          @type == :write
        end

        def connection_class
        end

        def connection_url
          @url
        end
      end
    end
  end
end
