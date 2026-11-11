# typed: true
# frozen_string_literal: true

ENV["OTEL_LOG_LEVEL"] ||= "fatal"

require "active_support"
require "github-telemetry"

if ENV["OTEL_PURE_RUBY_MONKEY_PATCH_ENABLED"] == "1"
  require "otel_exporter_monkey_patch"
end

module GitHub
  module Config
    module OpenTelemetry
      def tracer
        return @tracer if defined?(@tracer)

        @tracer = GitHub::Telemetry.tracer("github")
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
