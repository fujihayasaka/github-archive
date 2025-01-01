# frozen_string_literal: true
# typed: true

require "test_helper"

require "resilient/circuit_breaker"
require "vexi/circuit_breaker_config"

class CircuitBreakerConfigTest < Minitest::Test
  def setup
    @config = Vexi::CircuitBreakerConfig.new
  end

  def test_default_settings
    assert_equal(false, @config.force_open)
    assert_equal(false, @config.force_closed)
    assert_equal(5, @config.sleep_window_seconds)
    assert_equal(20, @config.request_volume_threshold)
    assert_equal(50, @config.error_threshold_percentage)
    assert_equal(60, @config.window_size_in_seconds)
    assert_equal(10, @config.bucket_size_in_seconds)
  end

  def test_modified_property
    @config.force_open = true

    assert_equal(true, @config.force_open)
  end

  def test_to_h
    @config.force_open = true

    expected = {
      force_open: true,
      force_closed: false,
      sleep_window_seconds: 5,
      request_volume_threshold: 20,
      error_threshold_percentage: 50,
      window_size_in_seconds: 60,
      bucket_size_in_seconds: 10
    }

    actual = @config.to_h

    assert_same_elements(expected, actual)
  end

  def test_breaker_creation_configuration
    circuit_breaker_config = Vexi::CircuitBreakerConfig.new(
      force_open: true,
      force_closed: true,
      sleep_window_seconds: 1,
      request_volume_threshold: 1,
      error_threshold_percentage: 1,
      window_size_in_seconds: 10,
      bucket_size_in_seconds: 1,
    )

    test_circuit_breaker = T.let(Resilient::CircuitBreaker.get("test", circuit_breaker_config.to_h), Resilient::CircuitBreaker)

    assert_equal(circuit_breaker_config.force_open, test_circuit_breaker.properties.force_open)
    assert_equal(circuit_breaker_config.force_closed, test_circuit_breaker.properties.force_closed)
    assert_equal(circuit_breaker_config.sleep_window_seconds, test_circuit_breaker.properties.sleep_window_seconds)
    assert_equal(circuit_breaker_config.request_volume_threshold, test_circuit_breaker.properties.request_volume_threshold)
    assert_equal(circuit_breaker_config.error_threshold_percentage, test_circuit_breaker.properties.error_threshold_percentage)
    assert_equal(circuit_breaker_config.window_size_in_seconds, test_circuit_breaker.properties.window_size_in_seconds)
    assert_equal(circuit_breaker_config.bucket_size_in_seconds, test_circuit_breaker.properties.bucket_size_in_seconds)
  end
end
