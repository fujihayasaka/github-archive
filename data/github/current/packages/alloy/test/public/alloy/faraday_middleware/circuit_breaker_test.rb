# typed: true
# frozen_string_literal: true

require "test_helper"

class AlloyFaradayMiddlewareCircuitBreakerTest < GitHub::TestCase
  test "uses a separate circuit per app" do
    app_circuit = circuit_breaker("app")
    other_app_circuit = circuit_breaker("other_app")

    assert_equal 0, app_circuit.metrics.successes
    assert_equal 0, other_app_circuit.metrics.successes

    res = mock_render_request(status: 200, app_name: "app")
    assert_equal 200, res.status
    assert_equal "OK", res.body
    assert_equal 1, app_circuit.metrics.successes
    assert_equal 0, other_app_circuit.metrics.successes
  end

  test "successful request with closed circuit breaker" do
    assert_equal 0, circuit_breaker.metrics.successes

    res = mock_render_request(status: 200)
    assert_equal 200, res.status
    assert_equal "OK", res.body
    assert_equal 1, circuit_breaker.metrics.successes
  end

  test "failed request with closed circuit breaker" do
    assert_equal 0, circuit_breaker.metrics.failures

    res = mock_render_request(status: 500)
    assert_equal 500, res.status
    assert_equal "OK", res.body
    assert_equal 1, circuit_breaker.metrics.failures
  end

  test "4xx is a failed request" do
    assert_equal 0, circuit_breaker.metrics.failures

    res = mock_render_request(status: 418)
    assert_equal 418, res.status
    assert_equal "OK", res.body
    assert_equal 1, circuit_breaker.metrics.failures
  end

  test "successful request with open circuit breaker" do
    10.times { circuit_breaker.failure }
    assert_equal 0, circuit_breaker.metrics.successes
    assert_equal 10, circuit_breaker.metrics.failures

    res = mock_render_request(status: 200)
    assert_equal 502, res.status
    assert GitHub::FaradayMiddleware::Resilient.tripped?(res), res.headers.inspect
    assert_equal 0, circuit_breaker.metrics.successes
    assert_equal 10, circuit_breaker.metrics.failures
  end

  test "failed request with open circuit breaker" do
    10.times { circuit_breaker.failure }
    assert_equal 0, circuit_breaker.metrics.successes
    assert_equal 10, circuit_breaker.metrics.failures

    res = mock_render_request(status: 500)
    assert_equal 502, res.status
    assert GitHub::FaradayMiddleware::Resilient.tripped?(res), res.headers.inspect
    assert_equal 0, circuit_breaker.metrics.successes
    assert_equal 10, circuit_breaker.metrics.failures
  end

  test "response on open circuit" do
    10.times { circuit_breaker.failure }

    res = mock_render_request(status: 200)
    assert_equal 502, res.status
    assert_equal "yes", res.headers[:resilient]
  end

  test "otel span attributes" do
    # capture circuit breaker state before request
    expected_attributes = {
      "circuit_breaker.key" => circuit_breaker.key.name,
      "circuit_breaker.error_threshold_percentage" => circuit_breaker.properties.error_threshold_percentage,
      "circuit_breaker.request_volume_threshold" => circuit_breaker.properties.request_volume_threshold,
      "circuit_breaker.window_size" => circuit_breaker.properties.window_size_in_seconds,
      "circuit_breaker.bucket_size" => circuit_breaker.properties.bucket_size_in_seconds,
      "circuit_breaker.circuit_open" => circuit_breaker.open,
      "circuit_breaker.current_error_percentage" => circuit_breaker.metrics.error_percentage,
      "circuit_breaker.total_requests" => circuit_breaker.metrics.requests,
    }

    mock_render_request(status: 200)

    span = find_span_by(name: "gh.alloy.faraday_client.request")

    assert_equal expected_attributes, span.attributes
  end

  test "otel span status ok when request allowed" do
    assert_predicate circuit_breaker, :allow_request?

    res = mock_render_request(status: 200)

    span = find_span_by(name: "gh.alloy.faraday_client.request")
    assert_predicate(span.status, :ok?)
  end

  test "otel span status error when circuit open" do
    10.times { circuit_breaker.failure }

    refute_predicate circuit_breaker, :allow_request?

    res = mock_render_request(status: 200)

    span = find_span_by(name: "gh.alloy.faraday_client.request")
    refute_predicate(span.status, :ok?)
  end

  private

  def circuit_breaker(app_name = "test")
    Resilient::CircuitBreaker.get("alloy.#{app_name}", {
      instrumenter: GitHub,
      request_volume_threshold: 5,
      sleep_window_seconds: 10,
      error_threshold_percentage: 5,
      window_size_in_seconds: 30,
      bucket_size_in_seconds: 5,
    })
  end

  sig { params(status: Integer, app_name: String).returns(T.untyped) }
  def mock_render_request(status:, app_name: "test")
    stub_faraday(status: status).post("/render", "{}", { Alloy::Constants::REACT_APP_HEADER => app_name })
  end

  def stub_faraday(status:, app_name: "test")
    Faraday.new(url: "http://example.invalid") do |b| # rubocop:disable GitHub/RequireExplicitInternalOrExternalFaradayClientWrapper
      b.use Alloy::FaradayMiddleware::CircuitBreaker
      b.adapter :test do |stub|
        stub.post("/render") do
          [status, { "Content-Type" => "text/plain" }, "OK"]
        end
      end
    end
  end
end
