# typed: true
# frozen_string_literal: true

require "opentelemetry-exporter-otlp"
require_relative "otel_pure_ruby_encoder"

module OpenTelemetry
  module Exporter
    module OTLP
      class Exporter
        alias_method :original_encode, :encode

        # Override encode to bypass google-protobuf object creation
        # and use our pure Ruby binary encoder directly.
        def encode(span_data)
          start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          begin
            OpenTelemetry::Proto::SimpleEncoder::Trace.encode_export_trace_service_request(span_data)
          rescue StandardError => e
            OpenTelemetry.handle_error(exception: e, message: "unexpected error in OTLP::Exporter#encode (pure ruby)")
            nil
          ensure
            stop = Process.clock_gettime(Process::CLOCK_MONOTONIC)
            duration_ms = 1000.0 * (stop - start)
            @metrics_reporter.record_value("otel.otlp_exporter.encode_duration", value: duration_ms)
          end
        end
        private :encode, :original_encode
      end
    end
  end
end
