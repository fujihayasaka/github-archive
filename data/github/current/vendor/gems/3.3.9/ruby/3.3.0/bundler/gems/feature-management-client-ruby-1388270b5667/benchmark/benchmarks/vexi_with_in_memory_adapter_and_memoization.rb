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

class InMemoryAdapterOnlyWithMemoizationBenchmarkTest < Minitest::Test
  extend T::Sig

  SETUP_NAME = "Vexi and Flipper configured with in-memory adapter and memoization enabled: "

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
      builder.custom_gates_evaluator.serial_gate_and_actor_evaluator(
        {
          "very_fast_custom_gate_that_returns_true" => ->(feature, actor) { true },
          "very_fast_custom_gate_that_returns_false" => ->(feature, actor) { false },
        }
      )
    end
    @vexi.memoize = true

    Flipper.unregister_groups
    @flipper = Flipper.new(Flipper::Adapters::Memory.new)
    @flipper.memoize = false
    @flipper.memoize = true
    Flipper.register("very_fast_custom_gate_that_returns_true") do |actor, context|
      true
    end
    Flipper.register("very_fast_custom_gate_that_returns_false") do |actor, context|
      false
    end

    @benchmark = VexiVersusFlipperBenchmarkHelper.new(@vexi, @flipper)
  end

  def test_enabled_check_for_a_flag_that_does_not_exist
    @benchmark.run(SETUP_NAME + "Flag that does not exist", "non_existent_flag")
  end

  def test_enabled_check_for_a_flag_that_does_not_exist_and_passing_an_actor
    actor = BenchmarkActor.new
    @benchmark.run(SETUP_NAME + "Flag that does not exist and passing an actor", "non_existent_flag", [actor])
  end

  def test_fully_enabled_flag_without_actor
    @vexi_adapter.enable("fully_enabled_flag")
    @flipper.enable("fully_enabled_flag")
    @benchmark.run(SETUP_NAME + "Flag that exists and is fully enabled", "fully_enabled_flag")
  end

  def test_fully_enabled_flag_with_actor
    actor = BenchmarkActor.new
    @benchmark.run(SETUP_NAME + "Flag that exists and is fully enabled and passing an actor", "fully_enabled_flag", [actor])
  end

  def test_50_percent_actor_shipped_flag
    @vexi_adapter.create(Vexi::FeatureFlag.new("50_actor_shipped_flag"))
    @vexi_adapter.enable_percentage_of_actors("50_actor_shipped_flag", 50.0)
    @flipper.enable_percentage_of_actors("50_actor_shipped_flag", 50.0)
    @benchmark.run(SETUP_NAME + "Flag that exists and is 50% actor shipped", "50_actor_shipped_flag")
  end

  def test_50_percent_actor_shipped_flag_with_actor
    @vexi_adapter.create(Vexi::FeatureFlag.new("50_actor_shipped_flag"))
    @vexi_adapter.enable_percentage_of_actors("50_actor_shipped_flag", 50.0)
    actor = BenchmarkActor.new
    @benchmark.run(SETUP_NAME + "Flag that exists and is 50% actor shipped and passing an actor", "50_actor_shipped_flag", [actor])
  end

  def test_50_percent_dark_shipped_flag
    @vexi_adapter.create(Vexi::FeatureFlag.new("50_dark_shipped_flag"))
    @vexi_adapter.enable_percentage_of_calls("50_dark_shipped_flag", 50.0)
    @flipper.enable_percentage_of_time("50_dark_shipped_flag", 50.0)
    @benchmark.run(SETUP_NAME + "Flag that exists and is 50% dark shipped", "50_dark_shipped_flag")
  end

  def test_explicit_actor_that_exists_on_flag
    @vexi_adapter.create(Vexi::FeatureFlag.new("explicit_actor_flag"))
    actor = BenchmarkActor.new("User:1234678")
    @vexi_adapter.add_actor("explicit_actor_flag", actor)
    @flipper.enable_actor("explicit_actor_flag", actor)
    @benchmark.run(SETUP_NAME + "Flag that exists and has the actor we are looking for explicitly added", "explicit_actor_flag", [actor])
  end

  def test_when_ten_thousand_actors_are_added_to_a_flag
    flag_name = "ten_thousand_actors_flag"
    flag = Vexi::FeatureFlag.new(flag_name)
    @vexi_adapter.create(flag)
    10_000.times do |i|
      actor = BenchmarkActor.new("User:#{i}")
      @vexi_adapter.add_actor(flag_name, actor)
      @flipper.enable_actor(flag_name, actor)
    end
    @benchmark.run(SETUP_NAME + "Flag that exists with 10,000 actors and has the actor we are looking for explicitly added", flag_name, [BenchmarkActor.new("User:7025")])
  end

  def test_when_ten_thousand_actors_are_added_to_a_flag_and_we_are_looking_for_an_actor_that_does_not_exist
    flag_name = "ten_thousand_actors_flag"
    flag = Vexi::FeatureFlag.new(flag_name)
    @vexi_adapter.create(flag)
    10_000.times do |i|
      actor = BenchmarkActor.new("User:#{i}")
      @vexi_adapter.add_actor(flag_name, actor)
      @flipper.enable_actor(flag_name, actor)
    end
    @benchmark.run(SETUP_NAME + "Flag that exists with 10,000 actors and has the actor we are looking is not present", flag_name, [BenchmarkActor.new("User:NotExists")])
  end

  def test_when_ten_thousand_actors_are_added_to_a_flag_and_we_are_looking_for_three_actors_that_exist
    flag_name = "ten_thousand_actors_flag"
    flag = Vexi::FeatureFlag.new(flag_name)
    @vexi_adapter.create(flag)
    10_000.times do |i|
      actor = BenchmarkActor.new("User:#{i}")
      @vexi_adapter.add_actor(flag_name, actor)
      @flipper.enable_actor(flag_name, actor)
    end
    @benchmark.run(SETUP_NAME + "Flag that exists with 10,000 actors and has the 3 actors we are checking for", flag_name, [BenchmarkActor.new("User:1025"), BenchmarkActor.new("User:4125"), BenchmarkActor.new("User:7027")])
  end

  def test_when_a_single_custom_gate_is_enabled_and_it_returns_true
    actor = BenchmarkActor.new("User:1234678")
    @vexi_adapter.create(Vexi::FeatureFlag.new("custom_gate_flag"))
    vexi_adapter.add_custom_gate("custom_gate_flag", "very_fast_custom_gate_that_returns_true")
    @flipper.enable_group("custom_gate_flag", "very_fast_custom_gate_that_returns_true")
    @benchmark.run(SETUP_NAME + "Flag that exists and has a single custom gate enabled and it returns true", "custom_gate_flag", [actor])
  end

  def test_when_a_single_custom_gate_is_enabled_and_it_returns_false
    actor = BenchmarkActor.new("User:1234678")
    @vexi_adapter.create(Vexi::FeatureFlag.new("custom_gate_flag"))
    vexi_adapter.add_custom_gate("custom_gate_flag", "very_fast_custom_gate_that_returns_false")
    @flipper.enable_group("custom_gate_flag", "very_fast_custom_gate_that_returns_false")
    @benchmark.run(SETUP_NAME + "Flag that exists and has a single custom gate enabled and it returns false", "custom_gate_flag", [actor])
  end

  def test_worst_case_scenario_where_all_gates_exist_on_flag_but_none_of_them_evaluate_to_true
    flag_name = "worst_case_flag"
    flag = Vexi::FeatureFlag.new(flag_name)
    @vexi_adapter.create(flag)
    10_000.times do |i|
      actor = BenchmarkActor.new("User:#{i}")
      @vexi_adapter.add_actor(flag_name, actor)
      @flipper.enable_actor(flag_name, actor)
    end
    @vexi_adapter.enable_percentage_of_calls(flag_name, 0.01)
    @flipper.enable_percentage_of_time(flag_name, 0.01)
    @vexi_adapter.enable_percentage_of_actors(flag_name, 0.01)
    @flipper.enable_percentage_of_actors(flag_name, 0.01)
    @vexi_adapter.add_custom_gate(flag_name, "very_fast_custom_gate_that_returns_false")
    @flipper.enable_group(flag_name, "very_fast_custom_gate_that_returns_false")
    @benchmark.run(SETUP_NAME + "Flag that exists and has all gates enabled but none of them evaluate to true", flag_name, [BenchmarkActor.new("User:NotExists")])
  end

  def test_worst_case_scenario_where_all_gates_except_dark_ship_exist_on_flag_but_none_of_them_evaluate_to_true
    flag_name = "worst_case_flag"
    flag = Vexi::FeatureFlag.new(flag_name)
    @vexi_adapter.create(flag)
    10_000.times do |i|
      actor = BenchmarkActor.new("User:#{i}")
      @vexi_adapter.add_actor(flag_name, actor)
      @flipper.enable_actor(flag_name, actor)
    end
    @vexi_adapter.enable_percentage_of_actors(flag_name, 0.01)
    @flipper.enable_percentage_of_actors(flag_name, 0.01)
    @vexi_adapter.add_custom_gate(flag_name, "very_fast_custom_gate_that_returns_false")
    @flipper.enable_group(flag_name, "very_fast_custom_gate_that_returns_false")

    @benchmark.run(SETUP_NAME + "Flag that exists and has all gates except dark ship enabled but none of them evaluate to true", flag_name, [BenchmarkActor.new("User:NotExists")])
  end

  def test_worst_case_scenario_where_all_gates_except_dark_ship_exist_on_flag_and_only_custom_gate_evaluates_to_true
    flag_name = "worst_case_flag"
    flag = Vexi::FeatureFlag.new(flag_name)
    @vexi_adapter.create(flag)
    10_000.times do |i|
      actor = BenchmarkActor.new("User:#{i}")
      @vexi_adapter.add_actor(flag_name, actor)
      @flipper.enable_actor(flag_name, actor)
    end
    @vexi_adapter.enable_percentage_of_actors(flag_name, 0.01)
    @flipper.enable_percentage_of_actors(flag_name, 0.01)
    @vexi_adapter.add_custom_gate(flag_name, "very_fast_custom_gate_that_returns_true")
    @flipper.enable_group(flag_name, "very_fast_custom_gate_that_returns_true")

    @benchmark.run(SETUP_NAME + "Flag that exists and has all gates except dark ship enabled and only custom gate evaluates to true", flag_name, [BenchmarkActor.new("User:NotExists")])
  end
end
