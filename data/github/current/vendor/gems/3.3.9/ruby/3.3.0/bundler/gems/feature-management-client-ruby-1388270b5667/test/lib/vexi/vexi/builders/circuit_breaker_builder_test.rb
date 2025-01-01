# frozen_string_literal: true
# typed: true

require "test_helper"
require "faraday"

require "vexi/builders/circuit_breaker_builder"
require "vexi/configuration"

class CircuitBreakerBuilderTest < Minitest::Test
  def setup
    @config = Vexi::Configuration.new
    @circuit_breaker_builder = Vexi::Builders::CircuitBreakerBuilder.new(@config)
  end

  def test_with_adapter_circuit_breaker
    circuit_breaker_config = Vexi::CircuitBreakerConfig.new

    @circuit_breaker_builder.with_adapter_circuit_breaker(circuit_breaker_config)

    assert_equal(circuit_breaker_config, @config.adapter_breaker_config)
  end

  def test_with_cache_circuit_breaker
    circuit_breaker_config = Vexi::CircuitBreakerConfig.new

    @circuit_breaker_builder.with_cache_circuit_breaker(circuit_breaker_config)

    assert_equal(circuit_breaker_config, @config.cache_breaker_config)
  end
end
