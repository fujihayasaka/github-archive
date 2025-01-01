# typed: true
# frozen_string_literal: true
ENV["OTEL_LOG_LEVEL"] ||= "fatal"

require "active_support"
require "github-telemetry"

module GitHub
  module Config
    module OpenTelemetry

      def tracer
        return @tracer if defined?(@tracer)

        @tracer = GitHub::Telemetry.tracer
      end

      def shutdown_tracer
        tracer_provider.try(:force_flush)
        tracer_provider.try(:shutdown)
      end

      def current_span
        ::OpenTelemetry::Trace.current_span
      end

      def context_propagation_map
        Hash.new.tap do |carrier|
          ::OpenTelemetry.propagation.inject(carrier)
        end
      end

      def tracer_provider
        ::OpenTelemetry.tracer_provider
      end

      def semconv_enabled?
        @semconv_enabled == true
      end
      attr_writer :semconv_enabled

      def logger
        @logger ||= GitHub::Telemetry::Logs.logger("GitHub")
      end

      def otel_logger_enabled?
        @otel_logger_enabled == true
      end
      attr_writer :otel_logger_enabled
    end
  end
  extend Config::OpenTelemetry
end

module FaradayWithPurge
  def self.extended(mod)
    updated_map = ::Faraday::Connection::METHODS.each_with_object({ purge: "PURGE" }) { |method, hash| hash[method] = method.to_s.upcase }
    mod.send(:remove_const, :HTTP_METHODS_SYMBOL_TO_STRING)
    mod.const_set(:HTTP_METHODS_SYMBOL_TO_STRING, updated_map)
  end
end
