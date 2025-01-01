# frozen_string_literal: true
# typed: true

require "sorbet-runtime"

# Disable sorbet runtime checks
T::Configuration.default_checked_level = :never

require "minitest/autorun"
require "mocha/minitest"
require "benchmark/ips"
require "flipper"

require "vexi"
require_relative "../utilities/garbage_collection"
require_relative "../utilities/benchmark_actor"
require_relative "../utilities/vexi_vs_flipper_benchmark_helper"

class InMemoryAdapterOnlyBenchmarkTest < Minitest::Test
  extend T::Sig

  SETUP_NAME = "Vexi and Flipper configured with in-memory adapter only: "

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

    @garbage_collection_disabled_suite = GarbageCollectionDisabledSuite.new

    @vexi_adapter = Vexi::Adapters::InMemoryAdapter.new(Vexi::Adapters::InMemoryAdapterMode::DisabledByDefault)
    @vexi = Vexi.build do |builder|
      builder.adapter.custom(@vexi_adapter)
    end

    @flipper = Flipper.new(Flipper::Adapters::Memory.new)
    @benchmark = VexiVersusFlipperBenchmarkHelper.new(@vexi, @flipper)
  end

  def test_enabled_check_for_a_flag_that_does_not_exist
    @benchmark.run(SETUP_NAME + "Flag that does not exist", "non_existent_flag")
  end

  def test_enabled_check_for_a_flag_that_does_not_exist_and_passing_an_actor
    actor = BenchmarkActor.new
    @benchmark.run(SETUP_NAME + "Flag that does not exist and passing an actor", "non_existent_flag", [actor])
  end
end
