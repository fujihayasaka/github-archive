# frozen_string_literal: true

require "benchmark/ips"
require "opentelemetry/sdk"
require "opentelemetry-exporter-otlp"
require_relative "../../lib/otel_pure_ruby_encoder"

# --- Setup Data ---
tracer_provider = OpenTelemetry::SDK::Trace::TracerProvider.new
tracer = tracer_provider.tracer("benchmark-tracer", "1.0.0")

spans = []
100.times do |i|
  span = tracer.start_span(
    "benchmark-span-#{i}",
    attributes: {
      "string_attr" => "value-#{i}",
      "int_attr" => i,
      "bool_attr" => i.even?,
      "float_attr" => i * 1.5,
      "array_attr" => [1, 2, 3]
    },
    kind: :server,
    start_timestamp: Time.now
  )
  span.add_event("event-#{i}", attributes: { "foo" => "bar" })
  span.finish(end_timestamp: Time.now + 0.1)
  spans << span.to_span_data
end

puts "Benchmarking with #{spans.size} spans..."

# --- Helper for Original Encoding ---
# This replicates the logic in the OTLP exporter to build the Protobuf objects
def encode_original(span_data)
  request = Opentelemetry::Proto::Collector::Trace::V1::ExportTraceServiceRequest.new(
    resource_spans: span_data
      .group_by(&:resource)
      .map do |resource, span_datas|
        Opentelemetry::Proto::Trace::V1::ResourceSpans.new(
          resource: Opentelemetry::Proto::Resource::V1::Resource.new(
            attributes: resource.attribute_enumerator.map { |key, value| as_otlp_key_value(key, value) }
          ),
          scope_spans: span_datas
            .group_by(&:instrumentation_scope)
            .map do |il, sds|
              Opentelemetry::Proto::Trace::V1::ScopeSpans.new(
                scope: Opentelemetry::Proto::Common::V1::InstrumentationScope.new(
                  name: il.name,
                  version: il.version
                ),
                spans: sds.map { |sd| as_otlp_span(sd) }
              )
            end
        )
      end
  )
  Opentelemetry::Proto::Collector::Trace::V1::ExportTraceServiceRequest.encode(request)
end

def as_otlp_key_value(key, value)
  Opentelemetry::Proto::Common::V1::KeyValue.new(key: key, value: as_otlp_any_value(value))
end

def as_otlp_any_value(value)
  result = Opentelemetry::Proto::Common::V1::AnyValue.new
  case value
  when String
    result.string_value = value
  when Integer
    result.int_value = value
  when Float
    result.double_value = value
  when true, false
    result.bool_value = value
  when Array
    result.array_value = Opentelemetry::Proto::Common::V1::ArrayValue.new(
      values: value.map { |v| as_otlp_any_value(v) }
    )
  end
  result
end

def as_otlp_span(span_data)
  Opentelemetry::Proto::Trace::V1::Span.new(
    trace_id: span_data.trace_id,
    span_id: span_data.span_id,
    trace_state: span_data.tracestate.to_s,
    parent_span_id: span_data.parent_span_id == OpenTelemetry::Trace::INVALID_SPAN_ID ? nil : span_data.parent_span_id,
    name: span_data.name,
    kind: as_otlp_span_kind(span_data.kind),
    start_time_unix_nano: span_data.start_timestamp,
    end_time_unix_nano: span_data.end_timestamp,
    attributes: (span_data.attributes || {}).map { |k, v| as_otlp_key_value(k, v) },
    dropped_attributes_count: span_data.total_recorded_attributes - (span_data.attributes&.length || 0),
    events: (span_data.events || []).map do |event|
      Opentelemetry::Proto::Trace::V1::Span::Event.new(
        time_unix_nano: event.timestamp,
        name: event.name,
        attributes: event.attributes.map { |k, v| as_otlp_key_value(k, v) }
      )
    end,
    dropped_events_count: span_data.total_recorded_events - (span_data.events&.length || 0),
    links: (span_data.links || []).map do |link|
      Opentelemetry::Proto::Trace::V1::Span::Link.new(
        trace_id: link.span_context.trace_id,
        span_id: link.span_context.span_id,
        trace_state: link.span_context.trace_state.to_s,
        attributes: link.attributes.map { |k, v| as_otlp_key_value(k, v) },
        dropped_attributes_count: 0
      )
    end,
    dropped_links_count: span_data.total_recorded_links - (span_data.links&.length || 0),
    status: as_otlp_status(span_data.status)
  )
end

def as_otlp_span_kind(kind)
  case kind
  when :internal then Opentelemetry::Proto::Trace::V1::Span::SpanKind::SPAN_KIND_INTERNAL
  when :server   then Opentelemetry::Proto::Trace::V1::Span::SpanKind::SPAN_KIND_SERVER
  when :client   then Opentelemetry::Proto::Trace::V1::Span::SpanKind::SPAN_KIND_CLIENT
  when :producer then Opentelemetry::Proto::Trace::V1::Span::SpanKind::SPAN_KIND_PRODUCER
  when :consumer then Opentelemetry::Proto::Trace::V1::Span::SpanKind::SPAN_KIND_CONSUMER
  else Opentelemetry::Proto::Trace::V1::Span::SpanKind::SPAN_KIND_UNSPECIFIED
  end
end

def as_otlp_status(status)
  return nil unless status

  code = case status.code
  when OpenTelemetry::Trace::Status::OK then Opentelemetry::Proto::Trace::V1::Status::StatusCode::STATUS_CODE_OK
  when OpenTelemetry::Trace::Status::ERROR then Opentelemetry::Proto::Trace::V1::Status::StatusCode::STATUS_CODE_ERROR
  else Opentelemetry::Proto::Trace::V1::Status::StatusCode::STATUS_CODE_UNSET
  end

  Opentelemetry::Proto::Trace::V1::Status.new(
    message: status.description,
    code: code
  )
end

# --- Benchmark ---

# Ractor setup for off-main-thread encoding
# We define a Ractor that runs the pure Ruby encoder in a loop
encoder_response_port = Ractor::Port.new
encoder_ractor = Ractor.new(encoder_response_port) do |response_port|
  loop do
    # Receive spans (will be deep copied since they are not frozen/shareable)
    batch = Ractor.receive
    break if batch == :shutdown

    # Perform encoding
    encoded = OpenTelemetry::Proto::SimpleEncoder::Trace.encode_export_trace_service_request(batch)

    # Return result via the response port
    response_port << encoded
  end
end

Benchmark.ips do |x|
  x.report("original exporter (google-protobuf)") do
    # This is a proxy for how much other work we can do on the main thread, as a result
    # of encoding on a dedicated ractor.
    t = Thread.new do ||
      encode_original(spans)
    end
    encode_original(spans)
    t.join
  end

  x.report("pure ruby encoder (main thread)") do
    t = Thread.new do ||
      OpenTelemetry::Proto::SimpleEncoder::Trace.encode_export_trace_service_request(spans)
    end
    OpenTelemetry::Proto::SimpleEncoder::Trace.encode_export_trace_service_request(spans)
    t.join
  end

  x.report("pure ruby encoder (ractor)") do
    t = Thread.new do ||
      OpenTelemetry::Proto::SimpleEncoder::Trace.encode_export_trace_service_request(spans)
    end
    encoder_ractor << spans
    encoder_response_port.receive
    t.join
  end

  x.compare!
end

# Clean up the Ractor
encoder_ractor << :shutdown
