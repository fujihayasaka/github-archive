# frozen_string_literal: true
# typed: true

require "test_helper"
require "faraday"

require "vexi/builder"
require "vexi/builders/adapter_builder"
require "vexi/builders/cache_builder"
require "vexi/builders/circuit_breaker_builder"
require "vexi/builders/custom_gates_evaluator_builder"
require "vexi/configuration"

class BuilderTest < Minitest::Test
  def setup
    @config = Vexi::Configuration.new
    @builder = Vexi::Builder.new(@config)
  end

  def test_adapter
    assert_instance_of(Vexi::Builders::AdapterBuilder, @builder.adapter)
  end

  def test_cache
    assert_instance_of(Vexi::Builders::CacheBuilder, @builder.cache)
  end

  def test_circuit_breaker
    assert_instance_of(Vexi::Builders::CircuitBreakerBuilder, @builder.circuit_breaker)
  end

  def test_custom_gates_evaluator
    assert_instance_of(Vexi::Builders::CustomGatesEvaluatorBuilder, @builder.custom_gates_evaluator)
  end

  def test_fallback_evaluator
    fallback_evaluator = -> (_feature_flag_name, _actors) { true }

    @builder.fallback_evaluator(fallback_evaluator)

    assert_equal(fallback_evaluator, @config.fallback_evaluator)
  end
end
