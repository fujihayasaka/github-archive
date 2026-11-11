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

# --- Ractor Setup ---

# This Ractor simulates the "Background Worker".
# It receives the payload and simulates the encoding work (by actually doing it).
# However, for the benchmark of "Offload Cost", we want to know how long the Main Thread is blocked
# by the `send` operation.
#
# Note: Ractor.receive copies the data. Ractor.send(obj) initiates the copy.
sink_response_port = Ractor::Port.new
sink_ractor = Ractor.new(sink_response_port) do |response_port|
  loop do
    data = Ractor.receive
    break if data == :shutdown
    result = OpenTelemetry::Proto::SimpleEncoder::Trace.encode_export_trace_service_request(data)
    response_port << result
  end
end

# --- Benchmark ---

Benchmark.ips do |x|
  x.report("Main Thread: Perform Encoding") do
    OpenTelemetry::Proto::SimpleEncoder::Trace.encode_export_trace_service_request(spans)
  end

  x.report("Main Thread: Offload to Ractor (Copy Cost)") do
    sink_ractor << spans
    _result = sink_response_port.receive
  end

  x.compare!
end

# Clean up the Ractor
sink_ractor << :shutdown
