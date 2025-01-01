# frozen_string_literal: true
# typed: true

require "test_helper"

require "vexi/actor_collection"
require "vexi/client"
require "vexi/version"
require "testing/test_actor"

class Vexi::ClientTest < Minitest::Test
  include MockFactory

  def setup
    @adapter = create_mock_adapter
    @cache = create_mock_cache
    @cache_config = Vexi::CacheConfig.new(@cache, 300, 30)
    @feature_flag_service = create_mock_feature_flag_service
    @segment_service = create_mock_segment_service
    @custom_gates_evaluator = create_mock_custom_gates_evaluator

    @instrumenter = Vexi::Observability::Notification.new
    @config = Vexi::Configuration.new(adapter: @adapter, cache_config: @cache_config, custom_gates_evaluator: @custom_gates_evaluator)

    Vexi::Notifications.instrumenter = T.let(@instrumenter, Vexi::Observability::Notification)

    @vexi = Vexi::Client.new(@config, @feature_flag_service, @segment_service)
  end

  # Test that enabled? returns false if feature flag service could not find feature flag
  def test_enabled_returns_false_if_feature_flag_does_not_exist
    @feature_flag_service.expects(:get).returns(nil)
    @instrumenter.expects(:instrument)

    refute @vexi.enabled?("does-not-exist")
  end

  # Test that enabled? emits the appropriate timing events and tags
  def test_enabled_emits_timing_event
    @feature_flag_service.expects(:get).returns(nil)

    @instrumenter.expects(:instrument).with("vexi.is_enabled.duration", {
      config: {
        memoization_enabled: false,
        adapter_name: "test_adapter",
        adapter_version: nil,
        caching_enabled: true,
        cache_name: "test_cache",
        custom_gates_evaluator_enabled: true,
        custom_gates_evaluator_name: "test_evaluator",
        vexi_version: Vexi::VERSION,
      },
      operation: "is_enabled",
      measured_start: anything,
      measured_finish: anything,
      number_of_actors_being_checked: 0,
      result: false,
      feature_flag_name: "does-not-exist",
    })

    @vexi.enabled?("does-not-exist")
  end

  # Test that enabled? return false if feature flag service throws an error
  def test_enabled_returns_false_if_feature_flag_service_get_raises_error
    @feature_flag_service.expects(:get).raises(StandardError)
    @instrumenter.expects(:instrument)

    refute @vexi.enabled?("does-not-exist")
  end

  # Test that enabled? evaluates the fallback evaluator if the feature flag service throws an error
  def test_enabled_evaluates_fallback_evaluator_if_feature_flag_service_get_raises_error
    # `anything` doesn't seem to work for nested hashes so we're stubbing this here
    time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    Process.stubs(:clock_gettime).with(Process::CLOCK_MONOTONIC).returns(time)
    error = StandardError.new("Boom!")

    @feature_flag_service.expects(:get).raises(error)

    @instrumenter.expects(:instrument).with("vexi.is_enabled.duration", {
      config: {
        memoization_enabled: false,
        adapter_name: "test_adapter",
        adapter_version: nil,
        caching_enabled: true,
        cache_name: "test_cache",
        custom_gates_evaluator_enabled: true,
        custom_gates_evaluator_name: "test_evaluator",
        vexi_version: Vexi::VERSION,
      },
      "feature_flag.adapter.error": {
        error: error,
        message: "error getting feature flag",
      },
      fallback_evaluator: {
        measured_start: time,
        measured_finish: time,
        result: true,
      },
      operation: "is_enabled",
      measured_start: time,
      measured_finish: time,
      number_of_actors_being_checked: 0,
      result: true,
      feature_flag_name: "feature",
    })

    fallback_evaluator_called = T.let(false, T::Boolean)
    fallback_evaluator = proc do |_feature_flag_name, _actors|
      fallback_evaluator_called = true
      true
    end

    @config.fallback_evaluator = fallback_evaluator
    vexi = Vexi::Client.new(@config, @feature_flag_service, @segment_service)

    assert vexi.enabled?("feature")
    assert fallback_evaluator_called
  end

  # Test that enabled? returns true if boolean gate evaluator returns true
  def test_enabled_returns_true_if_boolean_gate_evaluates_to_true
    boolean_flag = Vexi::FeatureFlag.create_boolean_feature_flag("boolean-true", true)

    @feature_flag_service.expects(:get).returns(boolean_flag)
    Vexi::NonActorGateEvaluator.expects(:evaluate_boolean_gate).with(boolean_flag).returns(true)
    @instrumenter.expects(:instrument)

    assert @vexi.enabled?("boolean-true")
  end

  # Test that enabled? returns true if percentage of calls evaluator returns true
  def test_enabled_returns_true_if_percentage_of_calls_is_true
    percentage_flag = Vexi::FeatureFlag.new("percentage-of-calls-false", percentage_of_calls: 80.0)

    @feature_flag_service.expects(:get).returns(percentage_flag)
    Vexi::NonActorGateEvaluator.expects(:evaluate_percentage_of_calls).with(percentage_flag).returns(true)
    @instrumenter.expects(:instrument)

    assert @vexi.enabled?(percentage_flag.name)
  end

  # Test that enabled? returns true if percentage of actors evalutor returns true
  def test_enabled_returns_false_if_percentage_of_actors_is_true
    actor_ids = ["actor-1"]
    percentage_flag = Vexi::FeatureFlag.new("percentage-of-actors-true", percentage_of_actors: 80.0)

    @feature_flag_service.expects(:get).returns(percentage_flag)
    Vexi::NonActorGateEvaluator.expects(:evaluate_percentage_of_actors).with(percentage_flag, actor_ids).returns(true)
    @instrumenter.expects(:instrument)

    assert @vexi.enabled?(percentage_flag.name, *actor_ids)
  end

  # Test that enabled? returns true if embedded actors evaluator returns true
  def test_enabled_returns_true_if_embedded_actors_is_true
    actor_ids = %w[actor-1 actor-2]
    actors = T.let(Vexi::HashActorCollection.new({ "actor" => true, "actor-2" => true }), Vexi::ActorCollection)
    actors_flag = Vexi::FeatureFlag.new("actors-true", actors: actors)

    @feature_flag_service.expects(:get).returns(actors_flag)
    Vexi::NonActorGateEvaluator.expects(:evaluate_embedded_actors).with(actors_flag.actors, actor_ids).returns(true)
    @instrumenter.expects(:instrument)
    assert @vexi.enabled?(actors_flag.name, *actor_ids)
  end

  # Test that enabled? increments error count and logs if get segment raises error
  def test_enabled_increments_error_count_and_logs_if_get_segment_raises_error
    feature = Vexi::FeatureFlag.create_boolean_feature_flag("segment-err", false)
    feature.segments = ["segment-1"]

    @feature_flag_service.expects(:get).returns(feature)
    expects_non_actor_gate_evaluator_all_false
    @segment_service.expects(:mget).raises(StandardError)
    @instrumenter.expects(:instrument)

    refute @vexi.enabled?("segment-err")
  end

  # Test that enabled? evaluates the fallback evaluator at the very if the segment service throws an error and
  # all other gates evaluate to false.
  def test_enabled_evaluates_fallback_evaluator_if_segment_service_get_raises_error
    feature = Vexi::FeatureFlag.create_boolean_feature_flag("segment-err", false)
    feature.custom_gates = ["gate-1"]

    @feature_flag_service.expects(:get).returns(feature)
    expects_non_actor_gate_evaluator_all_false
    @segment_service.expects(:mget).raises(StandardError)
    @instrumenter.expects(:instrument)
    @custom_gates_evaluator.expects(:enabled?).returns(false)

    fallback_evaluator_called = T.let(false, T::Boolean)
    fallback_evaluator = proc do |_feature_flag_name, _actors|
      fallback_evaluator_called = true
      true
    end

    @config.fallback_evaluator = fallback_evaluator
    vexi = Vexi::Client.new(@config, @feature_flag_service, @segment_service)

    assert vexi.enabled?("segment-err", "actor-1")
    assert fallback_evaluator_called
  end

  # Test that enabled? returns true if after getting segments and embedded actors evaluator returns true
  def test_enabled_returns_true_if_embedded_actors_is_true_after_getting_segments
    feature = Vexi::FeatureFlag.new("feature")
    segment = Vexi::Segment.new("segment-1", actors: Vexi::HashActorCollection.new({ "actor-1" => true }))

    @feature_flag_service.expects(:get).returns(feature)
    expects_non_actor_gate_evaluator_all_false # the intial nonactor gate evaluators
    @segment_service.expects(:mget).returns([segment])
    Vexi::NonActorGateEvaluator.expects(:evaluate_embedded_actors).with(segment.actors, ["actor-1"]).returns(true)
    @instrumenter.expects(:instrument)

    assert @vexi.enabled?(feature.name, "actor-1")
  end

  # Test that enabled? returns false if exhausted all other evaluations and custom_gate_evaluator is nil
  def test_enabled_returns_false_if_all_evaluations_return_false_and_custom_gate_evaluator_is_nil
    feature = Vexi::FeatureFlag.new("feature", custom_gates: ["gate-1"])

    segment = Vexi::Segment.new("segment-1", actors: Vexi::HashActorCollection.new({ "actor-2" => true }))

    @feature_flag_service.expects(:get).returns(feature)

    Vexi::NonActorGateEvaluator.expects(:evaluate_boolean_gate).returns(false)
    Vexi::NonActorGateEvaluator.expects(:evaluate_percentage_of_calls).returns(false)
    Vexi::NonActorGateEvaluator.expects(:evaluate_percentage_of_actors).returns(false)
    Vexi::NonActorGateEvaluator.expects(:evaluate_embedded_actors).returns(false).twice

    @segment_service.expects(:mget).returns([segment])
    @vexi.instance_variable_set(:@custom_gate_evaluator, nil)
    @instrumenter.expects(:instrument)

    refute @vexi.enabled?(feature.name, "actor-1")
  end

  # Test that enabled? returns true if custom_gate_evaluator returns true
  def test_enabled_returns_true_if_custom_gate_evaluator_returns_true
    # `anything` doesn't seem to work for nested hashes so we're stubbing this here
    time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    Process.stubs(:clock_gettime).with(Process::CLOCK_MONOTONIC).returns(time)

    feature = Vexi::FeatureFlag.new("feature", custom_gates: ["gate-1"])

    @feature_flag_service.expects(:get).returns(feature)
    expects_non_actor_gate_evaluator_all_false
    @segment_service.expects(:mget).returns([])
    @custom_gates_evaluator.expects(:enabled?).with(feature.name, feature.custom_gates, ["actor-1"]).returns(true)
    @instrumenter.expects(:instrument).with("vexi.is_enabled.duration", {
      feature_flag_name: "feature",
      number_of_actors_being_checked: 1,
      result: true,
      operation: "is_enabled",
      measured_start: time,
      measured_finish: time,
      custom_gates: {
        result: true,
        measured_start: time,
        measured_finish: time
      },
      config: {
        memoization_enabled: false,
        adapter_name: "test_adapter",
        adapter_version: nil,
        caching_enabled: true,
        cache_name: "test_cache",
        custom_gates_evaluator_enabled: true,
        custom_gates_evaluator_name: "test_evaluator",
        vexi_version: Vexi::VERSION,
      },
    })

    assert @vexi.enabled?(feature.name, "actor-1")
  end

  # Test that enabled? returns true if custom_gate_evaluator returns true for actor
  def test_enabled_returns_true_if_custom_gate_evaluator_returns_true_for_actor
    feature = Vexi::FeatureFlag.new("feature", custom_gates: ["gate-1"])
    actor_id = "actor-1"
    actor = TestActor.new(actor_id)

    @feature_flag_service.expects(:get).returns(feature)
    expects_non_actor_gate_evaluator_all_false
    @segment_service.expects(:mget).returns([])
    @custom_gates_evaluator.expects(:enabled?).with(feature.name, feature.custom_gates, [actor]).returns(true)
    @instrumenter.expects(:instrument)

    assert @vexi.enabled?(feature.name, actor)
  end

  # Test that enabled? returns false if custom_gate_evaluator returns false
  def test_enabled_returns_false_if_custom_gate_evaluator_returns_false
    feature = Vexi::FeatureFlag.new("feature", custom_gates: ["gate-1"])

    @feature_flag_service.expects(:get).returns(feature)
    expects_non_actor_gate_evaluator_all_false
    @segment_service.expects(:mget).returns([])
    @custom_gates_evaluator.expects(:enabled?).with(feature.name, feature.custom_gates, ["actor-1"]).returns(false)
    @instrumenter.expects(:instrument)

    refute @vexi.enabled?(feature.name, "actor-1")
  end

  # Test that enabled? returns false if custom_gate_evaluator raises an error
  def test_enabled_returns_false_if_custom_gate_evaluator_raises_error
    feature = Vexi::FeatureFlag.new("feature", custom_gates: ["gate-1"])

    @feature_flag_service.expects(:get).returns(feature)
    expects_non_actor_gate_evaluator_all_false
    @segment_service.expects(:mget).returns([])
    @custom_gates_evaluator.expects(:enabled?).with(
      feature.name, feature.custom_gates, ["actor-1"]
    ).raises(StandardError)
    @instrumenter.expects(:instrument)

    refute @vexi.enabled?(feature.name, "actor-1")
  end

  # Test that enabled? executes the fallback_evaluator if custom_gate_evaluator raises an error
  def test_enabled_executes_fallback_evaluator_if_custom_gate_evaluator_raises_error
    # anything doesn't seem to work for nested hashes so we're stubbing this here
    time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    Process.stubs(:clock_gettime).with(Process::CLOCK_MONOTONIC).returns(time)

    feature = Vexi::FeatureFlag.new("feature", custom_gates: ["gate-1"])

    @feature_flag_service.expects(:get).returns(feature)
    expects_non_actor_gate_evaluator_all_false
    @segment_service.expects(:mget).returns([])
    error = StandardError.new
    @custom_gates_evaluator.expects(:enabled?).with(
      feature.name, feature.custom_gates, ["actor-1"]
    ).raises(error)

    @instrumenter.expects(:instrument).with("vexi.is_enabled.duration", {
      config: {
        memoization_enabled: false,
        adapter_name: "test_adapter",
        adapter_version: nil,
        caching_enabled: true,
        cache_name: "test_cache",
        custom_gates_evaluator_enabled: true,
        custom_gates_evaluator_name: "test_evaluator",
        vexi_version: Vexi::VERSION,
      },
      feature_flag_name: feature.name,
      number_of_actors_being_checked: 1,
      result: true,
      operation: "is_enabled",
      measured_start: time,
      measured_finish: time,
      custom_gates: {
        measured_start: time,
        measured_finish: time,
      },
      "custom_gate_evaluator.error": {
        error: error,
        message: "error evaluating custom gates"
      },
      fallback_evaluator: {
        measured_start: time,
        measured_finish: time,
        result: true,
      },
    })

    fallback_evaluator_called = T.let(false, T::Boolean)
    fallback_evaluator = proc do |_feature_flag_name, _actors|
      fallback_evaluator_called = true
      true
    end

    @config.fallback_evaluator = fallback_evaluator
    vexi = Vexi::Client.new(@config, @feature_flag_service, @segment_service)

    assert vexi.enabled?(feature.name, "actor-1")
    assert fallback_evaluator_called
  end

  # Test that preload raises an error when no names provided
  def test_preload_with_empty_array
    assert_raises Vexi::Errors::ValidationError do
      @vexi.preload([])
    end
  end

  # Test that preload raises an error when no cache is configured and memoizing is not enabled
  def test_preload_raises_error_when_no_cache_and_memoizing_not_enabled
    vexi = Vexi::Client.new(Vexi::Configuration.new(adapter: @adapter), @feature_flag_service, @segment_service)

    assert_raises Vexi::Errors::ValidationError do
      vexi.preload(["feature1", "feature2"])
    end
  end

  # Test that preload calls get on feature_flag_service with the correct parameters when memoizing is enabled
  def test_preload_calls_get_on_feature_flag_service_when_memoizing_enabled
    vexi = Vexi::Client.new(Vexi::Configuration.new(adapter: @adapter), @feature_flag_service, @segment_service)

    feature1 = Vexi::FeatureFlag.new("feature1")
    feature2 = Vexi::FeatureFlag.new("feature2")

    @feature_flag_service.expects(:memoize=).with(true)
    @segment_service.expects(:memoize=).with(true)
    @feature_flag_service.expects(:mget).with(["feature1", "feature2"], fetch_directly_from_adapter: true, cache_without_expiry: false, raise_on_cache_breaker_open: false, instrumentation_context: anything).returns([feature1, feature2])
    @instrumenter.expects(:instrument).with("vexi.preload.duration", anything)

    vexi.memoize = true
    vexi.preload(["feature1", "feature2"])
  end

  # Test that preload emits the appropriate notification
  def test_preload_emits_observability_notification
    vexi = Vexi::Client.new(Vexi::Configuration.new(adapter: @adapter), @feature_flag_service, @segment_service)

    feature1 = Vexi::FeatureFlag.new("feature1")
    feature2 = Vexi::FeatureFlag.new("feature2")

    @feature_flag_service.expects(:memoize=).with(true)
    @segment_service.expects(:memoize=).with(true)
    @feature_flag_service.expects(:mget).with(["feature1", "feature2"], fetch_directly_from_adapter: true, cache_without_expiry: false, raise_on_cache_breaker_open: false, instrumentation_context: anything).returns([feature1, feature2])
    @instrumenter.expects(:instrument).with("vexi.preload.duration", {
      config: {
        memoization_enabled: true,
        adapter_name: "test_adapter",
        adapter_version: nil,
        caching_enabled: false,
        cache_name: nil,
        custom_gates_evaluator_enabled: false,
        custom_gates_evaluator_name: nil,
        vexi_version: Vexi::VERSION,
      },
      feature_flag_names: ["feature1", "feature2"],
      operation: "preload",
      measured_start: anything,
      measured_finish: anything,
      result: true,
      fetch_directly_from_adapter: true,
    })

    vexi.memoize = true
    vexi.preload(["feature1", "feature2"])
  end

  # Test that preload emits the appropriate notification when there is an adapter error when fetching feature flags.
  def test_preload_emits_observability_notification_when_adapter_error_fetching_feature_flags
    vexi = Vexi::Client.new(Vexi::Configuration.new(adapter: @adapter), @feature_flag_service, @segment_service)

    feature1 = Vexi::FeatureFlag.new("feature1")
    feature2 = Vexi::FeatureFlag.new("feature2")

    error = StandardError.new("Boom!")

    @feature_flag_service.expects(:memoize=).with(true)
    @segment_service.expects(:memoize=).with(true)
    @feature_flag_service.expects(:mget).with([feature1.name, feature2.name], fetch_directly_from_adapter: true, cache_without_expiry: false, raise_on_cache_breaker_open: false, instrumentation_context: anything).raises(error)
    @instrumenter.expects(:instrument).with("vexi.preload.duration", {
      config: {
        memoization_enabled: true,
        adapter_name: "test_adapter",
        adapter_version: nil,
        caching_enabled: false,
        cache_name: nil,
        custom_gates_evaluator_enabled: false,
        custom_gates_evaluator_name: nil,
        vexi_version: Vexi::VERSION,
      },
      "feature_flag.adapter.error": {
        error: error,
        message: "error getting feature flags",
      },
      feature_flag_names: [feature1.name, feature2.name],
      operation: "preload",
      measured_start: anything,
      measured_finish: anything,
      result: false,
      fetch_directly_from_adapter: true,
    })

    vexi.memoize = true
    vexi.preload([feature1.name, feature2.name])
  end

  # Test that preload emits the appropriate notification when there is an adapter erorr when fetching segments.
  def test_preload_emits_observability_notification_when_adapter_error_fetching_segments
    vexi = Vexi::Client.new(Vexi::Configuration.new(adapter: @adapter), @feature_flag_service, @segment_service)

    feature1 = Vexi::FeatureFlag.new("feature1")
    feature1.segments = ["segment1", "segment2"]
    feature2 = Vexi::FeatureFlag.new("feature2")
    feature2.segments = ["segment2", "segment3"]

    error = StandardError.new("Boom!")

    @feature_flag_service.expects(:memoize=).with(true)
    @segment_service.expects(:memoize=).with(true)
    @feature_flag_service.expects(:mget).with(["feature1", "feature2"], fetch_directly_from_adapter: true, cache_without_expiry: false, raise_on_cache_breaker_open: false, instrumentation_context: anything).returns([feature1, feature2])
    @segment_service.expects(:mget).with(["segment1", "segment2", "segment3"], fetch_directly_from_adapter: true, cache_without_expiry: false, raise_on_cache_breaker_open: false, instrumentation_context: anything).raises(error)
    @instrumenter.expects(:instrument).with("vexi.preload.duration", {
      config: {
        memoization_enabled: true,
        adapter_name: "test_adapter",
        adapter_version: nil,
        caching_enabled: false,
        cache_name: nil,
        custom_gates_evaluator_enabled: false,
        custom_gates_evaluator_name: nil,
        vexi_version: Vexi::VERSION,
      },
      "segment.adapter.error": {
        error: error,
        message: "error getting segments",
        segment_names: ["segment1", "segment2", "segment3"],
      },
      feature_flag_names: ["feature1", "feature2"],
      operation: "preload",
      measured_start: anything,
      measured_finish: anything,
      result: false,
      fetch_directly_from_adapter: true,
    })

    vexi.memoize = true
    vexi.preload(["feature1", "feature2"])
  end

  def test_preload_emits_observability_notification_with_custom_properties
    vexi = Vexi::Client.new(Vexi::Configuration.new(adapter: @adapter), @feature_flag_service, @segment_service)

    feature1 = Vexi::FeatureFlag.new("feature1")
    feature2 = Vexi::FeatureFlag.new("feature2")

    @feature_flag_service.expects(:memoize=).with(true)
    @segment_service.expects(:memoize=).with(true)
    @feature_flag_service.expects(:mget).with(["feature1", "feature2"], fetch_directly_from_adapter: true, cache_without_expiry: false, raise_on_cache_breaker_open: false, instrumentation_context: anything).returns([feature1, feature2])
    @instrumenter.expects(:instrument).with("vexi.preload.duration", {
      config: {
        memoization_enabled: true,
        adapter_name: "test_adapter",
        adapter_version: nil,
        caching_enabled: false,
        cache_name: nil,
        custom_gates_evaluator_enabled: false,
        custom_gates_evaluator_name: nil,
        vexi_version: Vexi::VERSION,
      },
      feature_flag_names: ["feature1", "feature2"],
      operation: "preload",
      measured_start: anything,
      measured_finish: anything,
      result: true,
      fetch_directly_from_adapter: true,
      # Custom properties
      hello: "World",
      custom_property: 1234,
    })

    vexi.memoize = true
    vexi.preload(["feature1", "feature2"], instrumentation_properties: {
      hello: "World",
      custom_property: 1234,
    })
  end

  # Test that preload calls get on feature_flag_service with the correct parameters when cache is enabled
  def test_preload_calls_get_on_feature_flag_service_when_cache_enabled
    vexi = Vexi::Client.new(Vexi::Configuration.new(adapter: @adapter, cache_config: @cache_config), @feature_flag_service, @segment_service)

    feature1 = Vexi::FeatureFlag.new("feature1")
    feature2 = Vexi::FeatureFlag.new("feature2")

    @feature_flag_service.expects(:mget).with(["feature1", "feature2"], fetch_directly_from_adapter: true, cache_without_expiry: false, raise_on_cache_breaker_open: false, instrumentation_context: anything).returns([feature1, feature2])
    @instrumenter.expects(:instrument).with("vexi.preload.duration", anything)

    vexi.preload(["feature1", "feature2"])
  end

  # Test that preload calls get on segment_service with the correct parameters containing the unique segments from the feature flags
  def test_preload_calls_get_on_segment_service
    vexi = Vexi::Client.new(Vexi::Configuration.new(adapter: @adapter, cache_config: @cache_config), @feature_flag_service, @segment_service)

    feature1 = Vexi::FeatureFlag.new("feature1", segments: ["segment1", "segment2"])
    feature2 = Vexi::FeatureFlag.new("feature2", segments: ["segment2", "segment3"])

    @feature_flag_service.expects(:mget).with(["feature1", "feature2"], fetch_directly_from_adapter: true, cache_without_expiry: false, raise_on_cache_breaker_open: false, instrumentation_context: anything).returns([feature1, feature2])
    @segment_service.expects(:mget).with(["segment1", "segment2", "segment3"], fetch_directly_from_adapter: true, cache_without_expiry: false, raise_on_cache_breaker_open: false, instrumentation_context: anything)
    @instrumenter.expects(:instrument).with("vexi.preload.duration", anything)

    vexi.preload(["feature1", "feature2"])
  end

  # Test that preload correctly handles the case when fetch_directly_from_adapter is true
  def test_preload_with_fetch_directly_from_adapter_true
    feature = Vexi::FeatureFlag.new("feature")

    @feature_flag_service.expects(:mget).with(["feature"], fetch_directly_from_adapter: true, cache_without_expiry: false, raise_on_cache_breaker_open: false, instrumentation_context: anything).returns([feature])
    @instrumenter.expects(:instrument).with("vexi.preload.duration", anything)

    @vexi.preload(["feature"], fetch_directly_from_adapter: true)
  end

  # Test that preload correctly handles the case when fetch_directly_from_adapter is false
  def test_preload_with_fetch_directly_from_adapter_false
    feature = Vexi::FeatureFlag.new("feature")

    @feature_flag_service.expects(:mget).with(["feature"], fetch_directly_from_adapter: false, cache_without_expiry: false, raise_on_cache_breaker_open: false, instrumentation_context: anything).returns([feature])
    @instrumenter.expects(:instrument).with("vexi.preload.duration", anything)

    @vexi.preload(["feature"], fetch_directly_from_adapter: false)
  end

  # Test that preload correctly passes on the value cache_without_expiry is true
  def test_preload_with_cache_without_expiry_true
    feature = Vexi::FeatureFlag.new("feature")

    @feature_flag_service.expects(:mget).with(["feature"], fetch_directly_from_adapter: true, cache_without_expiry: true, raise_on_cache_breaker_open: false, instrumentation_context: anything).returns([feature])
    @instrumenter.expects(:instrument).with("vexi.preload.duration", anything)

    @vexi.preload(["feature"], cache_without_expiry: true)
  end

  # Test that preload correctly passes on the value cache_without_expiry is false
  def test_preload_with_cache_without_expiry_false
    feature = Vexi::FeatureFlag.new("feature")

    @feature_flag_service.expects(:mget).with(["feature"], fetch_directly_from_adapter: true, cache_without_expiry: false, raise_on_cache_breaker_open: false, instrumentation_context: anything).returns([feature])
    @instrumenter.expects(:instrument).with("vexi.preload.duration", anything)

    @vexi.preload(["feature"], cache_without_expiry: false)
  end

  # Test that passing an actor object that does not include the vexi actor module and a nil actor leads to them being skipped for evaluation and is reported in the active support notification.
  def test_enabled_with_non_vexi_actor_object
    time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    Process.stubs(:clock_gettime).with(Process::CLOCK_MONOTONIC).returns(time)

    feature = Vexi::FeatureFlag.new("feature")
    valid_actor_1 = TestActor.new("actor-1")
    invalid_actor_2 = Object.new
    nil_actor_3 = nil
    invalid_actor_4 = Object.new
    nil_actor_5 = nil
    valid_actor_6 = TestActor.new("actor-6")

    @feature_flag_service.expects(:get).returns(feature)
    @segment_service.expects(:mget).returns([])

    @instrumenter.expects(:instrument).with("vexi.is_enabled.duration", {
      config: {
        memoization_enabled: false,
        adapter_name: "test_adapter",
        adapter_version: nil,
        caching_enabled: true,
        cache_name: "test_cache",
        custom_gates_evaluator_enabled: true,
        custom_gates_evaluator_name: "test_evaluator",
        vexi_version: Vexi::VERSION,
      },
      nil_actor_indices:  [2, 4],
      invalid_actor_type_indices: [1, 3],
      feature_flag_name: feature.name,
      number_of_actors_being_checked: 6,
      result: false,
      operation: "is_enabled",
      measured_start: time,
      measured_finish: time,
    })

    vexi = Vexi::Client.new(@config, @feature_flag_service, @segment_service)

    refute vexi.enabled?(feature.name, valid_actor_1, T.unsafe(invalid_actor_2), T.unsafe(nil_actor_3), T.unsafe(invalid_actor_4), T.unsafe(nil_actor_5), valid_actor_6)
  end

  private

  def expects_non_actor_gate_evaluator_all_false
    Vexi::NonActorGateEvaluator.expects(:evaluate_boolean_gate).returns(false)
    Vexi::NonActorGateEvaluator.expects(:evaluate_percentage_of_calls).returns(false)
    Vexi::NonActorGateEvaluator.expects(:evaluate_percentage_of_actors).returns(false)
    Vexi::NonActorGateEvaluator.expects(:evaluate_embedded_actors).returns(false)
  end
end
