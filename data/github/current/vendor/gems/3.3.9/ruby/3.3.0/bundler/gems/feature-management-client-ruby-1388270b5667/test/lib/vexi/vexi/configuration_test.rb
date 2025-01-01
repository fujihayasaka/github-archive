# frozen_string_literal: true
# typed: true

require "test_helper"
require "resilient/circuit_breaker"
require "vexi/client"
require "vexi/adapters/in_memory_adapter"
require "vexi/caches/in_memory"
require "vexi/circuit_breaker_config"
require "vexi/configuration"

class ConfigurationTest < Minitest::Test

  class TestAdapter
    include Vexi::Adapter

    def adapter_name; "test_adapter" end
    def check_actors_on_nonembedded_segments(_segments, _actors); end
    def get_feature_flags(_names); end
    def get_segments(_names); end
  end

  class TestCustomGatesEvaluator
    include Vexi::CustomGatesEvaluator

    def custom_gates_evaluator_name; "test_custom_gates_evaluator" end
    def enabled?(feature_name, custom_gate_names, actors); end
  end

  def setup
    @config = Vexi::Configuration.new
    Resilient::CircuitBreaker::Registry.reset
  end

  def test_configured_returns_false_when_no_adapter_is_set
    refute @config.configured?
  end

  def test_configured_returns_true_when_an_adapter_is_set
    adapter = TestAdapter.new
    @config.adapter = adapter

    assert @config.configured?
  end

  def test_create_instance_raises_exception_when_configuration_is_invalid
    error = assert_raises(Vexi::Configuration::ConfigurationError) do
      @config.create_instance
    end

    assert_equal("Invalid configuration: adapter was not configured", error.message)
  end

  def test_create_instance_returns_a_client
    adapter = TestAdapter.new
    @config.adapter = adapter

    client = @config.create_instance
    assert_kind_of(Vexi::Client, client)
  end

  def test_adapter_returns_adapter_when_configured
    adapter = TestAdapter.new
    @config.adapter = adapter

    assert_equal(adapter, @config.adapter)
  end

  def test_adapter_raises_error_when_none_was_configured
    error = assert_raises(Vexi::Configuration::ConfigurationError) do
      @config.adapter
    end

    assert_equal("Adapter was not configured", error.message)
  end

  def test_adapter_assignment_raises_error_when_already_configured
    @config.adapter = TestAdapter.new

    error = assert_raises(Vexi::Configuration::ConfigurationError) do
      @config.adapter = TestAdapter.new
    end

    assert_equal("Adapter already configured: test_adapter", error.message)
  end

  def test_cache_returns_configured_cache
    cache = Vexi::Caches::InMemory.new
    cache_config = Vexi::CacheConfig.new(cache, 300, 30)

    @config.cache_config = cache_config

    assert_equal(cache_config, @config.cache_config)
    assert_equal(cache, @config.cache_config.cache)
  end

  def test_cache_assignment_raises_error_when_already_configured
    @config.cache_config = Vexi::CacheConfig.new(Vexi::Caches::InMemory.new, 300, 30)

    assert_raises(Vexi::Configuration::ConfigurationError) do
      @config.cache_config = Vexi::CacheConfig.new(Vexi::Caches::InMemory.new, 300, 30)
    end
  end

  def test_circuit_breaker_created_from_circle_breaker_config
    @config.adapter_breaker_config = Vexi::CircuitBreakerConfig.new

    breaker =  Resilient::CircuitBreaker.get("adapter_breaker", @config.adapter_breaker_config.to_h)

    assert_equal(true, breaker.allow_request?)
  end

  def test_open_circuit_breaker_created_from_circle_breaker_config
    @config.adapter_breaker_config = Vexi::CircuitBreakerConfig.new(force_open: true)

    breaker =  Resilient::CircuitBreaker.get("adapter_breaker", @config.adapter_breaker_config.to_h)

    assert_equal(false, breaker.allow_request?)
  end

  def test_custom_gates_evaluator_returns_configured_evaluator
    custom_gates_evaluator = TestCustomGatesEvaluator.new

    @config.custom_gates_evaluator = custom_gates_evaluator

    assert_equal(custom_gates_evaluator, @config.custom_gates_evaluator)
  end

  def test_custom_gates_evaluator_assignment_raises_error_when_already_configured
    custom_gates_evaluator = TestCustomGatesEvaluator.new

    @config.custom_gates_evaluator = custom_gates_evaluator

    assert_raises(Vexi::Configuration::ConfigurationError) do
      @config.custom_gates_evaluator = custom_gates_evaluator
    end
  end

  def test_context_returns_populated_hash
    @config.adapter = TestAdapter.new

    assert_equal({
      adapter_name: "test_adapter",
      adapter_version: nil,
      cache_name: nil,
      caching_enabled: false,
      custom_gates_evaluator_name: nil,
      custom_gates_evaluator_enabled: false,
      vexi_version: Vexi::VERSION,
    }, @config.context)
  end

  def test_fallback_evaluator_returns_default
    assert_equal(Vexi::Configuration::DEFAULT_FALLBACK_EVALUATOR, @config.fallback_evaluator)
  end

  def test_fallback_evaluator_returns_configured_evaluator
    evaluator = -> (_feature_flag_name, _actors) { true }

    @config.fallback_evaluator = evaluator

    assert_equal(evaluator, @config.fallback_evaluator)
  end

  def test_valid_returns_false_without_adapter
    refute @config.valid?

    assert_equal(["adapter was not configured"], @config.errors)
  end

  def test_valid_returns_true_with_adapter
    @config.adapter = TestAdapter.new

    assert @config.valid?
    assert_empty(@config.errors)
  end
end
