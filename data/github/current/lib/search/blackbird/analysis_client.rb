# typed: true
# frozen_string_literal: true
require "blackbird-analysis"

module Search
  module Blackbird
    class AnalysisClient
      SERVICE_URL     = GitHub.blackbird_mw_analysis_url
      SERVICE_NAME    = "blackbird_mw_analysis"
      DEFAULT_TIMEOUT = 1.0
      EXCEPTIONS = [::Twirp::Error, ::Faraday::ConnectionFailed, ::Faraday::TimeoutError, SystemCallError, RuntimeError, ArgumentError, Encoding::UndefinedConversionError].freeze

      def self.query_async(args)
        if GitHub.blackbird_disable_analysis
          Promise.resolve(empty_response)
        else
          req = ::Blackbird::Analysis::V2::GetSymbolsRequest.new(args)
          resp = async_client.get_symbols(req)
          resp.then(
            proc { |r| process_response(r) },
            proc do |e|
              GitHub.logger.error("Failed", {
                :exception => e,
                "code.namespace" => self.name,
                "code.function" => __method__
                })
              {
                timed_out: false,
                not_analyzed: true,
                symbols: [],
              }
            end
          )
        end
      end

      def self.query(args)
        resp = if GitHub.blackbird_disable_analysis
          empty_response
        else
          begin
            req = ::Blackbird::Analysis::V2::GetSymbolsRequest.new(args)
            client.get_symbols(req)
          rescue *EXCEPTIONS => e
            GitHub.logger.error("Failed", {
              :exception => e,
              "code.namespace" => self.name,
              "code.function" => __method__
              })
            return {
              timed_out: false,
              not_analyzed: true,
              symbols: [],
            }
          end
        end

        process_response(resp)
      end

      def self.process_response(resp)
        if resp.error
          return {
            timed_out: true,
            not_analyzed: true,
            symbols: [],
            error: resp.error
          }
        end

        {
          timed_out: resp.data.timed_out,
          not_analyzed: resp.data.not_analyzed,
          symbols: resp.data.symbols.map do |s|
            h = s.to_h
            # TODO: Remove this once JavaScript front end transitions
            h[:kind] = if s.kind.is_a?(Symbol)
              s.kind.to_s.gsub("SYMBOL_KIND_", "").gsub(/_(D|R)EF/, "").downcase
            else
              "unknown"
            end
            h
          end
        }
      end

      def self.empty_response
        Twirp::ClientResp::new(
          data: ::Blackbird::Analysis::V2::GetSymbolsResponse::new,
          error: nil,
        )
      end

      def self.build_client(async:)
        connection_module = async ? ConcurrentFaraday : Faraday
        connection = connection_module.new(url: SERVICE_URL) do |conn|
          conn.use GitHub::FaradayMiddleware::RequestID
          conn.use GitHub::FaradayMiddleware::Datadog, stats: GitHub.dogstats, service_name: SERVICE_NAME
          conn.use GitHub::FaradayMiddleware::HMACAuth, hmac_key: GitHub.blackbird_mw_analysis_hmac_key
          conn.use GitHub::FaradayMiddleware::Resilient, name: SERVICE_NAME, options: {
            instrumenter: GitHub,
            sleep_window_seconds: 10,
            error_threshold_percentage: 5,
            window_size_in_seconds: 30,
            bucket_size_in_seconds: 5,
          }
          conn.options[:open_timeout] = DEFAULT_TIMEOUT # connection open timeout in seconds.
          conn.options[:timeout] = DEFAULT_TIMEOUT  # read timeout in seconds.

          if async
            conn.adapter :concurrent_adapter, persistent: true
          else
            conn.adapter :persistent_excon
          end
        end
        ::Blackbird::Analysis::V2::AnalysisAPIClient.new(connection)
      end

      def self.client
        @client ||= build_client(async: false)
      end

      def self.async_client
        @async_client ||= build_client(async: true)
      end
    end
  end
end
