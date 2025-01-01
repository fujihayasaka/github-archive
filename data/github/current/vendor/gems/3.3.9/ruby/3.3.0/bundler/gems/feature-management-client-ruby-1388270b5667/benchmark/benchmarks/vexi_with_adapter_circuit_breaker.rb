# frozen_string_literal: true
# typed: true

require "sorbet-runtime"

# Disable sorbet runtime checks
T::Configuration.default_checked_level = :never

require "minitest/autorun"
require "mocha/minitest"
require "benchmark/ips"
require "flipper"
require "timeout"

require "vexi"
require_relative "../utilities/garbage_collection"
require_relative "../utilities/benchmark_actor"
require_relative "../utilities/vexi_vs_flipper_benchmark_helper"

class InMemoryAdapterCircuitBreakerBenchmarkTest < Minitest::Test
  extend T::Sig

  SETUP_NAME = "Vexi configured with in-memory adapter and adapter circuit breaker: "

  class FlipperAdapterWithLatency < Flipper::Adapters::Memory
    def get(*args)
      sleep(0.0003) # 300 microseconds
      super
    end
  end

  class VexiAdapterWithLatency < Vexi::Adapters::InMemoryAdapter
    def get_feature_flags(*args)
      sleep(0.0003) # 300 microseconds
      super
    end
  end

  sig { returns(Vexi::Adapters::InMemoryAdapter) }
  attr_accessor :vexi_adapter

  sig { returns(Vexi::Client) }
  attr_accessor :vexi

  sig { returns(VexiVersusFlipperBenchmarkHelper) }
  attr_accessor :benchmark

  def setup
    # Reset thread-local client before each test
    Thread.current[:vexi_instance] = nil
    # Reset vexi configuration before each test
    Vexi.instance_variable_set(:@configuration, nil)
    # Clear all registered circuit breakers
    Resilient::CircuitBreaker::Registry.reset

    @garbage_collection_disabled_suite = GarbageCollectionDisabledSuite.new

    @vexi_adapter = VexiAdapterWithLatency.new(Vexi::Adapters::InMemoryAdapterMode::DisabledByDefault)
    @vexi = Vexi.build do |builder|
      builder.adapter.custom(@vexi_adapter)
      builder.circuit_breaker.with_adapter_circuit_breaker(Vexi::CircuitBreakerConfig.new)
    end

    @flipper = Flipper.new(FlipperAdapterWithLatency.new)
    @benchmark = VexiVersusFlipperBenchmarkHelper.new(@vexi, @flipper)
  end

  def test_enabled_check_for_a_flag_that_does_not_exist_with_adapter_breaker
    @benchmark.run(SETUP_NAME + "Flag that does not exist", "non_existent_flag")
  end
end
