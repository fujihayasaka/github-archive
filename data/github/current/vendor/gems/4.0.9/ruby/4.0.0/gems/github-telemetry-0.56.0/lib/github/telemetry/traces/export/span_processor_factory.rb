# frozen_string_literal: true

module GitHub
  module Telemetry
    module Traces
      module Export
        class SpanProcessorFactory
          PENDING_SPANS_ENABLED = "GITHUB_TELEMETRY_PENDING_SPANS_ENABLED"
          MAX_INT = 2**31 - 1

          # Creation method that instantiates a span processor based on the exporter
          #
          # - OTLP Exporters will always be paired with a BatchSpanProcessor
          # - Non-OTLP Exporters will always be paired with a SimpleSpanProcessor
          #
          # If the environment variable GITHUB_TELEMETRY_PENDING_SPANS_ENABLED is set to true, then
          # the BatchSpanProcessor will be wrapped in a PendingSpanProcessor to avoid dropping
          # spans when the application exits gracefully.
          #
          # @return OpenTelemetry::SDK::Trace::SpanProcessor
          def self.new_span_processor(exporter, metrics_reporter:)
            case exporter
            when OpenTelemetry::Exporter::OTLP::Exporter
              validate_otel_bsp_max_queue_size
              batch_processor = OpenTelemetry::SDK::Trace::Export::BatchSpanProcessor.new(exporter, metrics_reporter: metrics_reporter)

              if ENV.fetch(PENDING_SPANS_ENABLED, "true") == "true" && defined?(ActiveSupport::ForkTracker)
                pending_span_processor = GitHub::Telemetry::Traces::Export::PendingSpanProcessor.new(batch_processor, metrics_reporter: metrics_reporter, reset_on_fork: false)
                ActiveSupport::ForkTracker.after_fork { pending_span_processor.reset }
                return pending_span_processor
              end

              return batch_processor
            else
              OpenTelemetry::SDK::Trace::Export::SimpleSpanProcessor.new(exporter)
            end
          end

          private

          def self.validate_otel_bsp_max_queue_size
            max_queue_size_raw = ENV["OTEL_BSP_MAX_QUEUE_SIZE"]
            return unless max_queue_size_raw
            # The following validation matches the user experience in github-telemetry-go.

            # If it's not a valid integer, reset to default (no error).
            unless max_queue_size_raw.match?(/\A-?\d+\z/)
              ENV["OTEL_BSP_MAX_QUEUE_SIZE"] = "2048"
              return
            end

            # If it's an integer but out of range, raise an error.
            max_queue_size = max_queue_size_raw.to_i
            if max_queue_size < 0 || max_queue_size > MAX_INT
              raise ArgumentError, "unsupported value for OTEL_BSP_MAX_QUEUE_SIZE, please select a positive integer < maxInt"
            end
          end
        end
      end
    end
  end
end
