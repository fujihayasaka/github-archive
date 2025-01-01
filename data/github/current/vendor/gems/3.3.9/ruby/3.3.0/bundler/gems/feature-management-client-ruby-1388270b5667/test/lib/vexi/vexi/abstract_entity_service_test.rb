# frozen_string_literal: true
# typed: true

require "test_helper"
require "vexi/abstract_entity_service"
require "vexi/errors/circuit_breaker_open_error"
require "vexi/services/feature_flag_service"
require "vexi/models/feature_flag"

class TestEntityService < Vexi::AbstractEntityService
  extend T::Sig
  extend T::Generic # Provides `type_member` helper

  EntityType = type_member { { fixed: Vexi::FeatureFlag } }

  sig { override.returns(T::Class[EntityType]) }
  def entity_type
    Vexi::FeatureFlag
  end

  sig { override.returns(String) }
  def entity_type_name
    "feature_flag"
  end

  sig { params(entities: T::Array[EntityType]).void }
  def memoize_entities(entities)
    entities.each do |entity|
      @memoized_entities[entity.name] = entity
    end
  end

  sig { params(entity_names: T::Array[String]).returns(T::Array[EntityType]) }
  def get_memoized_entities(entity_names)
    entity_names.map { |entity_name| @memoized_entities[entity_name] }.compact
  end

  sig { override.params(name: String).returns(EntityType) }
  def get_default_entity_instance(name)
    @default_entities ||= {}
    @default_entities[name] ||= Vexi::FeatureFlag.create_default(name)
  end

  private

  sig { override.params(name: String).returns(String) }
  def get_cache_key(name);
    "vexi:ff:#{name}"
  end

  sig do
    override.params(names: T::Array[String]).returns(T::Array[Vexi::GetEntityResponse])
  end
  def get_entity_responses(names);
    @adapter.get_feature_flags(names)
  end
end

class AbstractEntityServiceTest < Minitest::Test
  include MockFactory

  def setup
    Resilient::CircuitBreaker::Registry.reset

    @adapter = create_mock_adapter

    @cache = create_mock_cache
    @cache_config = Vexi::CacheConfig.new(@cache, 300, 30)
    @test_service = TestEntityService.new(@adapter, @cache_config)
    @instrumentation_context = Vexi::InstrumentationContext.new

    @circuit_breaker_config = Vexi::CircuitBreakerConfig.new
    @adapter_circuit_breaker = T.let(Resilient::CircuitBreaker.get("adapter_breaker", @circuit_breaker_config.to_h), T.nilable(Resilient::CircuitBreaker))
    @cache_circuit_breaker = T.let(Resilient::CircuitBreaker.get("cache_breaker", @circuit_breaker_config.to_h), T.nilable(Resilient::CircuitBreaker))
    @test_service_with_breakers = TestEntityService.new(@adapter, @cache_config, @adapter_circuit_breaker, @cache_circuit_breaker)
  end

  def test_mget_from_memoized_entities
    time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    Process.stubs(:clock_gettime).with(Process::CLOCK_MONOTONIC).returns(time)

    @test_service.memoize = true
    memoized_flags = [
      Vexi::FeatureFlag.create_boolean_feature_flag("feature1", true),
      Vexi::FeatureFlag.create_boolean_feature_flag("feature2", false)
    ]

    @test_service.memoize_entities(memoized_flags)
    @cache
      .expects(:mget)
      .never
    @adapter
      .expects(:get_feature_flags)
      .never

    response = @test_service.mget(
      %w[feature1 feature2],
      fetch_directly_from_adapter: false,
      cache_without_expiry: false,
      _allow_context_overrides: false,
      instrumentation_context: @instrumentation_context
    )

    assert_same_elements memoized_flags, response
    assert_equal({
      "feature_flag.fetch_directly_from_adapter": false,
      "feature_flag.memoization.fetch": {
        entities_count: 2,
      }
    }, @instrumentation_context.to_h)
  end

  def test_mget_from_cache
    time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    Process.stubs(:clock_gettime).with(Process::CLOCK_MONOTONIC).returns(time)

    cached_flags = [
      Vexi::FeatureFlag.create_boolean_feature_flag("feature1", true),
      Vexi::FeatureFlag.create_boolean_feature_flag("feature2", false)
    ]

    @cache
      .expects(:mget)
      .with([get_feature_flag_cache_key(cached_flags[0].name), get_feature_flag_cache_key(cached_flags[1].name)])
      .returns(cached_flags)

    response = @test_service.mget(
      %w[feature1 feature2],
      fetch_directly_from_adapter: false,
      cache_without_expiry: false,
      _allow_context_overrides: false,
      instrumentation_context: @instrumentation_context
    )

    assert_same_elements cached_flags, response
    assert_equal({
      "feature_flag.fetch_directly_from_adapter": false,
      "feature_flag.memoization.fetch": {
        entities_count: 0,
      },
      "feature_flag.cache.fetch": {
        measured_start: time,
        measured_finish: time,
        entities_count: 2,
      },
    }, @instrumentation_context.to_h)
  end

  def test_mget_from_cache_with_circuit_breakers
    time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    Process.stubs(:clock_gettime).with(Process::CLOCK_MONOTONIC).returns(time)

    cached_flags = [
      Vexi::FeatureFlag.create_boolean_feature_flag("feature1", true),
      Vexi::FeatureFlag.create_boolean_feature_flag("feature2", false)
    ]

    @cache
      .expects(:mget)
      .with([get_feature_flag_cache_key(cached_flags[0].name), get_feature_flag_cache_key(cached_flags[1].name)])
      .returns(cached_flags)

    response = @test_service_with_breakers.mget(
      %w[feature1 feature2],
      fetch_directly_from_adapter: false,
      cache_without_expiry: false,
      _allow_context_overrides: false,
      instrumentation_context: @instrumentation_context
    )

    assert_same_elements cached_flags, response
    assert_equal({
      "feature_flag.fetch_directly_from_adapter": false,
      "feature_flag.memoization.fetch": {
        entities_count: 0,
      },
      "feature_flag.cache.fetch": {
        measured_start: time,
        measured_finish: time,
        entities_count: 2,
      },
    }, @instrumentation_context.to_h)
  end

  def test_mget_from_adapter
    time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    Process.stubs(:clock_gettime).with(Process::CLOCK_MONOTONIC).returns(time)

    adapter_flags = [
      Vexi::FeatureFlag.create_boolean_feature_flag("feature1", true),
      Vexi::FeatureFlag.create_boolean_feature_flag("feature2", false)
    ]
    adapter_response = [
      Vexi::GetFeatureFlagResponse.new(name: adapter_flags[0].name, feature_flag: adapter_flags[0], error: nil),
      Vexi::GetFeatureFlagResponse.new(name: adapter_flags[1].name, feature_flag: adapter_flags[1], error: nil)
    ]

    @adapter
      .expects(:get_feature_flags)
      .with([adapter_flags[0].name, adapter_flags[1].name])
      .returns(adapter_response)
    @cache
      .expects(:mset)
      .with({
        get_feature_flag_cache_key(adapter_flags[0].name) => adapter_flags[0],
        get_feature_flag_cache_key(adapter_flags[1].name) => adapter_flags[1],
      }, @cache_config.ttl)

    response = @test_service.mget(
      %w[feature1 feature2],
      fetch_directly_from_adapter: true,
      cache_without_expiry: false,
      _allow_context_overrides: false,
      instrumentation_context: @instrumentation_context,
    )

    assert_same_elements adapter_flags, response
    assert_equal({
      "feature_flag.fetch_directly_from_adapter": true,
      "feature_flag.memoization.fetch": {
        entities_count: 0,
      },
      "feature_flag.cache.fetch": {
        measured_start: time,
        measured_finish: time,
        entities_count: 0,
      },
      "feature_flag.adapter.fetch": {
        measured_start: time,
        measured_finish: time,
        entities_count: 2,
      },
    }, @instrumentation_context.to_h)
  end

  def test_mget_from_adapter_with_circuit_breakers
    time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    Process.stubs(:clock_gettime).with(Process::CLOCK_MONOTONIC).returns(time)

    adapter_flags = [
      Vexi::FeatureFlag.create_boolean_feature_flag("feature1", true),
      Vexi::FeatureFlag.create_boolean_feature_flag("feature2", false)
    ]
    adapter_response = [
      Vexi::GetFeatureFlagResponse.new(name: adapter_flags[0].name, feature_flag: adapter_flags[0], error: nil),
      Vexi::GetFeatureFlagResponse.new(name: adapter_flags[1].name, feature_flag: adapter_flags[1], error: nil)
    ]

    @adapter
      .expects(:get_feature_flags)
      .with([adapter_flags[0].name, adapter_flags[1].name])
      .returns(adapter_response)
    @cache
      .expects(:mset)
      .with({
        get_feature_flag_cache_key(adapter_flags[0].name) => adapter_flags[0],
        get_feature_flag_cache_key(adapter_flags[1].name) => adapter_flags[1],
      }, @cache_config.ttl)

    response = @test_service_with_breakers.mget(
      %w[feature1 feature2],
      fetch_directly_from_adapter: true,
      cache_without_expiry: false,
      _allow_context_overrides: false,
      instrumentation_context: @instrumentation_context,
    )

    assert_same_elements adapter_flags, response
    assert_equal({
      "feature_flag.fetch_directly_from_adapter": true,
      "feature_flag.memoization.fetch": {
        entities_count: 0,
      },
      "feature_flag.cache.fetch": {
        measured_start: time,
        measured_finish: time,
        entities_count: 0,
      },
      "feature_flag.adapter.fetch": {
        measured_start: time,
        measured_finish: time,
        entities_count: 2,
      },
    }, @instrumentation_context.to_h)
  end

  def test_mget_from_memoized_entities_and_cache
    @test_service.memoize = true

    memoized_flags = [
      Vexi::FeatureFlag.create_boolean_feature_flag("feature1", true),
      Vexi::FeatureFlag.create_boolean_feature_flag("feature2", false)
    ]
    cached_flags = [
      Vexi::FeatureFlag.create_boolean_feature_flag("feature3", true),
      Vexi::FeatureFlag.create_boolean_feature_flag("feature4", false)
    ]

    @test_service.memoize_entities(memoized_flags)
    @cache
      .expects(:mget)
      .with([
        get_feature_flag_cache_key(cached_flags[0].name),
        get_feature_flag_cache_key(cached_flags[1].name)
      ])
      .returns(cached_flags)
    @adapter
      .expects(:get_feature_flags)
      .never

    response = @test_service.mget(
      %w[feature1 feature2 feature3 feature4],
      fetch_directly_from_adapter: false,
      cache_without_expiry: false,
      _allow_context_overrides: false
    )

    assert_same_elements [
      memoized_flags[0],
      memoized_flags[1],
      cached_flags[0],
      cached_flags[1]
    ], response
  end

  def test_mget_from_cache_and_adapter
    cached_flags = [
      Vexi::FeatureFlag.create_boolean_feature_flag("feature1", true),
      Vexi::FeatureFlag.create_boolean_feature_flag("feature2", false)
    ]
    flags_returned_by_adapter_flags = [
      Vexi::FeatureFlag.create_boolean_feature_flag("feature3", true),
      Vexi::FeatureFlag.create_boolean_feature_flag("feature4", false)
    ]
    adapter_response = [
      Vexi::GetFeatureFlagResponse.new(name: flags_returned_by_adapter_flags[0].name, feature_flag: flags_returned_by_adapter_flags[0], error: nil),
      Vexi::GetFeatureFlagResponse.new(name: flags_returned_by_adapter_flags[1].name, feature_flag: flags_returned_by_adapter_flags[1], error: nil)
    ]

    # initial cache check
    @cache
      .expects(:mget)
      .with([
        get_feature_flag_cache_key(cached_flags[0].name),
        get_feature_flag_cache_key(cached_flags[1].name),
        get_feature_flag_cache_key(flags_returned_by_adapter_flags[0].name),
        get_feature_flag_cache_key(flags_returned_by_adapter_flags[1].name)
      ])
      .returns(cached_flags)

    # adapter calls
    @adapter
      .expects(:get_feature_flags)
      .with([flags_returned_by_adapter_flags[0].name, flags_returned_by_adapter_flags[1].name])
      .returns(adapter_response)
    @cache
      .expects(:mset)
      .with({
        get_feature_flag_cache_key(flags_returned_by_adapter_flags[0].name) => flags_returned_by_adapter_flags[0],
        get_feature_flag_cache_key(flags_returned_by_adapter_flags[1].name) => flags_returned_by_adapter_flags[1],
      }, @cache_config.ttl)

    response = @test_service.mget(
      %w[feature1 feature2 feature3 feature4],
      fetch_directly_from_adapter: false,
      cache_without_expiry: false,
      _allow_context_overrides: false
    )

    assert_same_elements [
      cached_flags[0],
      cached_flags[1],
      flags_returned_by_adapter_flags[0],
      flags_returned_by_adapter_flags[1]
    ], response
  end

  # Test that we add execption to instrumentation context and fallback to the adapter in case cache.mget raises an exception
  def test_mget_from_cache_and_adapter_with_exception
    time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    Process.stubs(:clock_gettime).with(Process::CLOCK_MONOTONIC).returns(time)

    flags_returned_by_adapter_flags = [
      Vexi::FeatureFlag.create_boolean_feature_flag("feature1", true),
      Vexi::FeatureFlag.create_boolean_feature_flag("feature2", false)
    ]
    adapter_response = [
      Vexi::GetFeatureFlagResponse.new(name: flags_returned_by_adapter_flags[0].name, feature_flag: flags_returned_by_adapter_flags[0], error: nil),
      Vexi::GetFeatureFlagResponse.new(name: flags_returned_by_adapter_flags[1].name, feature_flag: flags_returned_by_adapter_flags[1], error: nil)
    ]

    error = StandardError.new("Boom!")

    # initial cache check
    @cache
      .expects(:mget)
      .with([
        get_feature_flag_cache_key(flags_returned_by_adapter_flags[0].name),
        get_feature_flag_cache_key(flags_returned_by_adapter_flags[1].name)
      ])
      .raises(error)

    # adapter calls
    @adapter
      .expects(:get_feature_flags)
      .with([flags_returned_by_adapter_flags[0].name, flags_returned_by_adapter_flags[1].name])
      .returns(adapter_response)
    @cache
      .expects(:mset)
      .with({
        get_feature_flag_cache_key(flags_returned_by_adapter_flags[0].name) => flags_returned_by_adapter_flags[0],
        get_feature_flag_cache_key(flags_returned_by_adapter_flags[1].name) => flags_returned_by_adapter_flags[1],
      }, @cache_config.ttl)

    response = @test_service.mget(
      %w[feature1 feature2],
      fetch_directly_from_adapter: false,
      cache_without_expiry: false,
      _allow_context_overrides: false,
      instrumentation_context: @instrumentation_context,
    )

    assert_same_elements [
      flags_returned_by_adapter_flags[0],
      flags_returned_by_adapter_flags[1]
    ], response

    assert_equal({
      "feature_flag.fetch_directly_from_adapter": false,
      "feature_flag.memoization.fetch": {
        entities_count: 0,
      },
      "feature_flag.cache.fetch": {
        measured_start: time,
        measured_finish: time,
      },
      "feature_flag.cache.fetch.error": {
        error: error,
        message: "Error fetching entities from cache",
      },
      "feature_flag.adapter.fetch": {
        measured_start: time,
        measured_finish: time,
        entities_count: 2,
      },
    }, @instrumentation_context.to_h)
  end

  def test_mget_from_cache_and_adapter_with_open_circuit_breakers
    breaker_config = Vexi::CircuitBreakerConfig.new(force_open: true)
    circuit_breaker = Resilient::CircuitBreaker.get("test_breaker", breaker_config.to_h)
    test_service_with_open_breakers = TestEntityService.new(@adapter, @cache_config, circuit_breaker, circuit_breaker)

    time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    Process.stubs(:clock_gettime).with(Process::CLOCK_MONOTONIC).returns(time)

    assert_raises(Vexi::Errors::CircuitBreakerOpenError) do
      test_service_with_open_breakers.mget(
        %w[feature1 feature2],
        fetch_directly_from_adapter: false,
        cache_without_expiry: false,
        raise_on_cache_breaker_open: true,
        _allow_context_overrides: false,
        instrumentation_context: @instrumentation_context,
      )
    end

    assert_equal({
      "feature_flag.fetch_directly_from_adapter": false,
      "feature_flag.memoization.fetch": {
        entities_count: 0,
      },
      "feature_flag.cache.fetch": {
        measured_start: time,
        measured_finish: time,
      },
      "feature_flag.cache.fetch.circuit_breaker_open": true,
    }, @instrumentation_context.to_h)
  end

  def test_mget_from_cache_and_adapter_with_open_cache_circuit_breaker_and_raise_on_cache_breaker_open_false
    breaker_config = Vexi::CircuitBreakerConfig.new(force_open: true)
    circuit_breaker = Resilient::CircuitBreaker.get("test_breaker", breaker_config.to_h)
    test_service_with_open_breakers = TestEntityService.new(@adapter, @cache_config, nil, circuit_breaker)

    time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    Process.stubs(:clock_gettime).with(Process::CLOCK_MONOTONIC).returns(time)

    flags_returned_by_adapter_flags = [
      Vexi::FeatureFlag.create_boolean_feature_flag("feature1", false),
      Vexi::FeatureFlag.create_boolean_feature_flag("feature2", false)
    ]

    adapter_response = [
      Vexi::GetFeatureFlagResponse.new(name: flags_returned_by_adapter_flags[0].name, feature_flag: flags_returned_by_adapter_flags[0], error: nil),
      Vexi::GetFeatureFlagResponse.new(name: flags_returned_by_adapter_flags[1].name, feature_flag: flags_returned_by_adapter_flags[1], error: nil)
    ]

    @adapter
      .expects(:get_feature_flags)
      .with([flags_returned_by_adapter_flags[0].name, flags_returned_by_adapter_flags[1].name])
      .returns(adapter_response)

    response = test_service_with_open_breakers.mget(
      %w[feature1 feature2],
      fetch_directly_from_adapter: false,
      cache_without_expiry: false,
      raise_on_cache_breaker_open: false,
      _allow_context_overrides: false,
      instrumentation_context: @instrumentation_context,
    )

    assert_equal(2, response.count)
    assert_equal(flags_returned_by_adapter_flags[0], response[0])
    assert_equal(flags_returned_by_adapter_flags[1], response[1])

    assert_equal({
      "feature_flag.fetch_directly_from_adapter": false,
      "feature_flag.memoization.fetch": {
        entities_count: 0,
      },
      "feature_flag.cache.fetch": {
        measured_start: time,
        measured_finish: time,
      },
      "feature_flag.cache.fetch.circuit_breaker_open": true,
      "feature_flag.adapter.fetch": {
        entities_count: 2,
        measured_start: time,
        measured_finish: time,
      },
      "feature_flag.cache.set.circuit_breaker_open": true,
    }, @instrumentation_context.to_h)
  end

  # Test that we add exception to instrumentation context and move on in case cache.mset raises an exception
  def test_mget_from_cache_and_adapter_with_exception_on_cache_mset
    time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    Process.stubs(:clock_gettime).with(Process::CLOCK_MONOTONIC).returns(time)

    flags_returned_by_adapter_flags = [
      Vexi::FeatureFlag.create_boolean_feature_flag("feature1", true),
      Vexi::FeatureFlag.create_boolean_feature_flag("feature2", false)
    ]
    adapter_response = [
      Vexi::GetFeatureFlagResponse.new(name: flags_returned_by_adapter_flags[0].name, feature_flag: flags_returned_by_adapter_flags[0], error: nil),
      Vexi::GetFeatureFlagResponse.new(name: flags_returned_by_adapter_flags[1].name, feature_flag: flags_returned_by_adapter_flags[1], error: nil)
    ]

    error = StandardError.new("Boom!")

    # initial cache check
    @cache
      .expects(:mget)
      .with([
        get_feature_flag_cache_key(flags_returned_by_adapter_flags[0].name),
        get_feature_flag_cache_key(flags_returned_by_adapter_flags[1].name)
      ])
      .returns([])
    @adapter
      .expects(:get_feature_flags)
      .with([flags_returned_by_adapter_flags[0].name, flags_returned_by_adapter_flags[1].name])
      .returns(adapter_response)
    @cache
      .expects(:mset)
      .with({
        get_feature_flag_cache_key(flags_returned_by_adapter_flags[0].name) => flags_returned_by_adapter_flags[0],
        get_feature_flag_cache_key(flags_returned_by_adapter_flags[1].name) => flags_returned_by_adapter_flags[1],
      }, @cache_config.ttl)
      .raises(error)

    response = @test_service.mget(
      %w[feature1 feature2],
      fetch_directly_from_adapter: false,
      cache_without_expiry: false,
      _allow_context_overrides: false,
      instrumentation_context: @instrumentation_context,
    )

    assert_same_elements [
      flags_returned_by_adapter_flags[0],
      flags_returned_by_adapter_flags[1]
    ], response

    assert_equal({
      "feature_flag.fetch_directly_from_adapter": false,
      "feature_flag.memoization.fetch": {
        entities_count: 0,
      },
      "feature_flag.cache.fetch": {
        measured_start: time,
        measured_finish: time,
        entities_count: 0,
      },
      "feature_flag.adapter.fetch": {
        measured_start: time,
        measured_finish: time,
        entities_count: 2,
      },
      "feature_flag.cache.set.error": {
        error: error,
        message: "Error setting entities in cache",
      },
    }, @instrumentation_context.to_h)
  end

  def test_mget_from_memoized_entities_and_adapter
    @test_service.memoize = true

    memoized_flags = [
      Vexi::FeatureFlag.create_boolean_feature_flag("feature1", true),
      Vexi::FeatureFlag.create_boolean_feature_flag("feature2", false)
    ]
    adapter_flags = [
      Vexi::FeatureFlag.create_boolean_feature_flag("feature3", true),
      Vexi::FeatureFlag.create_boolean_feature_flag("feature4", false)
    ]
    adapter_response = [
      Vexi::GetFeatureFlagResponse.new(name: adapter_flags[0].name, feature_flag: adapter_flags[0], error: nil),
      Vexi::GetFeatureFlagResponse.new(name: adapter_flags[1].name, feature_flag: adapter_flags[1], error: nil)
    ]

    @test_service.memoize_entities(memoized_flags)
    @cache
      .expects(:mget)
      .with([
        get_feature_flag_cache_key(adapter_flags[0].name),
        get_feature_flag_cache_key(adapter_flags[1].name)
      ])
      .returns([])
    @adapter
      .expects(:get_feature_flags)
      .with([adapter_flags[0].name, adapter_flags[1].name])
      .returns(adapter_response)
    @cache
      .expects(:mset)
      .with({
        get_feature_flag_cache_key(adapter_flags[0].name) => adapter_flags[0],
        get_feature_flag_cache_key(adapter_flags[1].name) => adapter_flags[1],
      }, @cache_config.ttl)

    response = @test_service.mget(
      %w[feature1 feature2 feature3 feature4],
      fetch_directly_from_adapter: false,
      cache_without_expiry: false,
      _allow_context_overrides: false
    )

    assert_same_elements [
      memoized_flags[0],
      memoized_flags[1],
      adapter_flags[0],
      adapter_flags[1]
    ], response
  end

  def test_mget_from_memoized_entities_and_cache_and_adapter
    @test_service.memoize = true

    memoized_flags = [
      Vexi::FeatureFlag.create_boolean_feature_flag("feature1", true),
      Vexi::FeatureFlag.create_boolean_feature_flag("feature2", false)
    ]
    cached_flags = [
      Vexi::FeatureFlag.create_boolean_feature_flag("feature3", true),
      Vexi::FeatureFlag.create_boolean_feature_flag("feature4", false)
    ]
    adapter_flags = [
      Vexi::FeatureFlag.create_boolean_feature_flag("feature5", true),
      Vexi::FeatureFlag.create_boolean_feature_flag("feature6", false)
    ]
    adapter_response = [
      Vexi::GetFeatureFlagResponse.new(name: adapter_flags[0].name, feature_flag: adapter_flags[0], error: nil),
      Vexi::GetFeatureFlagResponse.new(name: adapter_flags[1].name, feature_flag: adapter_flags[1], error: nil)
    ]

    @test_service.memoize_entities(memoized_flags)
    @cache
      .expects(:mget)
      .with([
        get_feature_flag_cache_key(cached_flags[0].name),
        get_feature_flag_cache_key(cached_flags[1].name),
        get_feature_flag_cache_key(adapter_flags[0].name),
        get_feature_flag_cache_key(adapter_flags[1].name)
      ])
      .returns(cached_flags)
    @adapter
      .expects(:get_feature_flags)
      .with([adapter_flags[0].name, adapter_flags[1].name])
      .returns(adapter_response)
    @cache
      .expects(:mset)
      .with({
        get_feature_flag_cache_key(adapter_flags[0].name) => adapter_flags[0],
        get_feature_flag_cache_key(adapter_flags[1].name) => adapter_flags[1],
      }, @cache_config.ttl)

    response = @test_service.mget(
      %w[feature1 feature2 feature3 feature4 feature5 feature6],
      fetch_directly_from_adapter: false,
      cache_without_expiry: false,
      _allow_context_overrides: false
    )

    assert_same_elements [
      memoized_flags[0],
      memoized_flags[1],
      cached_flags[0],
      cached_flags[1],
      adapter_flags[0],
      adapter_flags[1]
    ], response
  end

  def test_mget_from_memoized_entities_with_fetch_directly_from_adapter
    @test_service.memoize = true

    memoized_flags = [
      Vexi::FeatureFlag.create_boolean_feature_flag("feature1", true),
      Vexi::FeatureFlag.create_boolean_feature_flag("feature2", false)
    ]
    adapter_flags = [
      Vexi::FeatureFlag.create_boolean_feature_flag("feature1", true),
      Vexi::FeatureFlag.create_boolean_feature_flag("feature2", false)
    ]
    adapter_response = [
      Vexi::GetFeatureFlagResponse.new(name: adapter_flags[0].name, feature_flag: adapter_flags[0], error: nil),
      Vexi::GetFeatureFlagResponse.new(name: adapter_flags[1].name, feature_flag: adapter_flags[1], error: nil)
    ]

    @test_service.memoize_entities(memoized_flags)
    @cache
      .expects(:mget)
      .never
    @adapter
      .expects(:get_feature_flags)
      .with([adapter_flags[0].name, adapter_flags[1].name])
      .returns(adapter_response)
    @cache
      .expects(:mset)
      .with({
          get_feature_flag_cache_key(adapter_flags[0].name) => adapter_flags[0],
          get_feature_flag_cache_key(adapter_flags[1].name) => adapter_flags[1],
      }, @cache_config.ttl)

    response = @test_service.mget(
      %w[feature1 feature2],
      fetch_directly_from_adapter: true,
      cache_without_expiry: false,
      _allow_context_overrides: false
    )

    assert_same_elements [
      adapter_flags[0],
      adapter_flags[1]
    ], response
  end

  def test_mget_memoized_entities_population_from_cache
    @test_service.memoize = true

    cached_flags = [
      Vexi::FeatureFlag.create_boolean_feature_flag("feature1", true),
      Vexi::FeatureFlag.create_boolean_feature_flag("feature2", false)
    ]

    @cache
      .expects(:mget)
      .with([
        get_feature_flag_cache_key(cached_flags[0].name),
        get_feature_flag_cache_key(cached_flags[1].name)
      ])
      .returns(cached_flags)

    assert_same_elements [], @test_service.get_memoized_entities(%w[feature1 feature2])
    @test_service.mget(
      %w[feature1 feature2],
      fetch_directly_from_adapter: false,
      cache_without_expiry: false,
      _allow_context_overrides: false
    )
    assert_same_elements cached_flags, @test_service.get_memoized_entities(%w[feature1 feature2])
  end

  def test_mget_memoized_entities_population_from_adapter
    @test_service.memoize = true

    adapter_flags = [
      Vexi::FeatureFlag.create_boolean_feature_flag("feature1", true),
      Vexi::FeatureFlag.create_boolean_feature_flag("feature2", false)
    ]
    adapter_response = [
      Vexi::GetFeatureFlagResponse.new(name: adapter_flags[0].name, feature_flag: adapter_flags[0], error: nil),
      Vexi::GetFeatureFlagResponse.new(name: adapter_flags[1].name, feature_flag: adapter_flags[1], error: nil)
    ]

    @cache
      .expects(:mget)
      .with([
        get_feature_flag_cache_key(adapter_flags[0].name),
        get_feature_flag_cache_key(adapter_flags[1].name),
      ])
      .returns([])
    @adapter
      .expects(:get_feature_flags)
      .with([adapter_flags[0].name, adapter_flags[1].name])
      .returns(adapter_response)
    @cache
      .expects(:mset)
      .with({
        get_feature_flag_cache_key(adapter_flags[0].name) => adapter_flags[0],
        get_feature_flag_cache_key(adapter_flags[1].name) => adapter_flags[1],
      }, @cache_config.ttl)

    assert_same_elements [], @test_service.get_memoized_entities(%w[feature1 feature2])
    @test_service.mget(
      %w[feature1 feature2],
      fetch_directly_from_adapter: false,
      cache_without_expiry: false,
      _allow_context_overrides: false
    )
    assert_same_elements adapter_flags, @test_service.get_memoized_entities(%w[feature1 feature2])
  end

  def test_mget_memoized_entities_population_from_cache_and_adapter
    @test_service.memoize = true

    cached_flags = [
      Vexi::FeatureFlag.create_boolean_feature_flag("feature1", true),
      Vexi::FeatureFlag.create_boolean_feature_flag("feature2", false)
    ]
    adapter_flags = [
      Vexi::FeatureFlag.create_boolean_feature_flag("feature3", true),
      Vexi::FeatureFlag.create_boolean_feature_flag("feature4", false)
    ]
    adapter_response = [
      Vexi::GetFeatureFlagResponse.new(name: adapter_flags[0].name, feature_flag: adapter_flags[0], error: nil),
      Vexi::GetFeatureFlagResponse.new(name: adapter_flags[1].name, feature_flag: adapter_flags[1], error: nil)
    ]

    @cache
      .expects(:mget)
      .with([
        get_feature_flag_cache_key(cached_flags[0].name),
        get_feature_flag_cache_key(cached_flags[1].name),
        get_feature_flag_cache_key(adapter_flags[0].name),
        get_feature_flag_cache_key(adapter_flags[1].name),
      ])
      .returns(cached_flags)
    @adapter
      .expects(:get_feature_flags)
      .with([adapter_flags[0].name, adapter_flags[1].name])
      .returns(adapter_response)
    @cache
      .expects(:mset)
      .with({
        get_feature_flag_cache_key(adapter_flags[0].name) => adapter_flags[0],
        get_feature_flag_cache_key(adapter_flags[1].name) => adapter_flags[1],
      }, @cache_config.ttl)

    assert_same_elements [], @test_service.get_memoized_entities(%w[feature1 feature2 feature3 feature4])
    @test_service.mget(
      %w[feature1 feature2 feature3 feature4],
      fetch_directly_from_adapter: false,
      cache_without_expiry: false,
      _allow_context_overrides: false
    )
    assert_same_elements cached_flags + adapter_flags, @test_service.get_memoized_entities(%w[feature1 feature2 feature3 feature4])
  end

  def test_mget_setting_memoize_clears_memoized_entities
    memoized_flags = [
      Vexi::FeatureFlag.create_boolean_feature_flag("feature1", true),
      Vexi::FeatureFlag.create_boolean_feature_flag("feature2", false)
    ]

    @test_service.memoize = true
    @test_service.memoize_entities(memoized_flags)
    assert_same_elements memoized_flags, @test_service.get_memoized_entities(%w[feature1 feature2])

    @test_service.memoize = true # Calling memoize=() always clears even if the value is the same
    assert_same_elements [], @test_service.get_memoized_entities(%w[feature1 feature2])
  end

  def test_mget_from_cache_and_adapter_caches_not_found
    @test_service.memoize = true

    adapter_flags = [
      Vexi::FeatureFlag.create_boolean_feature_flag("feature1", true),
      Vexi::FeatureFlag.create_boolean_feature_flag("feature2", false)
    ]
    not_found_flags = [
      @test_service.get_default_entity_instance("feature3"),
      @test_service.get_default_entity_instance("feature4"),
    ]
    adapter_response = [
      Vexi::GetFeatureFlagResponse.new(name: adapter_flags[0].name, feature_flag: adapter_flags[0], error: nil),
      Vexi::GetFeatureFlagResponse.new(name: adapter_flags[1].name, feature_flag: adapter_flags[1], error: nil)
    ]
    # initial cache check, no results
    @cache
      .expects(:mget)
      .with([
        get_feature_flag_cache_key(adapter_flags[0].name),
        get_feature_flag_cache_key(adapter_flags[1].name),
        get_feature_flag_cache_key(not_found_flags[0].name),
        get_feature_flag_cache_key(not_found_flags[1].name)
      ])
      .returns([])

    # adapter calls
    @adapter
      .expects(:get_feature_flags)
      .with([adapter_flags[0].name, adapter_flags[1].name, not_found_flags[0].name, not_found_flags[1].name])
      .returns(adapter_response)
    @cache
      .expects(:mset)
      .with({
        get_feature_flag_cache_key(adapter_flags[0].name) => adapter_flags[0],
        get_feature_flag_cache_key(adapter_flags[1].name) => adapter_flags[1],
      }, @cache_config.ttl)
    @cache
      .expects(:mset)
      .with({
        get_feature_flag_cache_key(not_found_flags[0].name) => not_found_flags[0],
        get_feature_flag_cache_key(not_found_flags[1].name) => not_found_flags[1],
      }, @cache_config.not_found_ttl)

    response = @test_service.mget(
      %w[feature1 feature2 feature3 feature4],
      fetch_directly_from_adapter: false,
      cache_without_expiry: false,
      _allow_context_overrides: false
    )

    assert_same_elements adapter_flags + not_found_flags, @test_service.get_memoized_entities(%w[feature1 feature2 feature3 feature4])

    assert_same_elements [
      adapter_flags[0],
      adapter_flags[1],
      not_found_flags[0],
      not_found_flags[1]
    ], response
  end

  def test_mget_cache_without_expiry
    adapter_flags = [
      Vexi::FeatureFlag.create_boolean_feature_flag("feature1", true),
      Vexi::FeatureFlag.create_boolean_feature_flag("feature2", false)
    ]
    adapter_response = [
      Vexi::GetFeatureFlagResponse.new(name: adapter_flags[0].name, feature_flag: adapter_flags[0], error: nil),
      Vexi::GetFeatureFlagResponse.new(name: adapter_flags[1].name, feature_flag: adapter_flags[1], error: nil)
    ]

    @adapter
      .expects(:get_feature_flags)
      .with([adapter_flags[0].name, adapter_flags[1].name])
      .returns(adapter_response)
    @cache
      .expects(:mset)
      .with({
        get_feature_flag_cache_key(adapter_flags[0].name) => adapter_flags[0],
        get_feature_flag_cache_key(adapter_flags[1].name) => adapter_flags[1],
      }, Vexi::Cache::TTL_NEVER_EXPIRE)

    response = @test_service.mget(
      %w[feature1 feature2],
      fetch_directly_from_adapter: true,
      cache_without_expiry: true,
      _allow_context_overrides: false
    )

    assert_same_elements adapter_flags, response
  end

  def test_get_from_memoized
    @test_service.memoize = true

    time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    Process.stubs(:clock_gettime).with(Process::CLOCK_MONOTONIC).returns(time)

    name = "feature1"

    memoized_flag = Vexi::FeatureFlag.create_boolean_feature_flag(name, true)
    @test_service.memoize_entities([memoized_flag])

    response = @test_service.get(
      name,
      fetch_directly_from_adapter: false,
      cache_without_expiry: false,
      _allow_context_overrides: false,
      instrumentation_context: @instrumentation_context
    )

    assert_equal memoized_flag, response
    assert_equal({
      "feature_flag.memoization.fetch": {
        entities_count: 1,
      },
    }, @instrumentation_context.to_h)
  end

  def test_get_from_cache
    time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    Process.stubs(:clock_gettime).with(Process::CLOCK_MONOTONIC).returns(time)

    name = "feature1"

    cached_flag = Vexi::FeatureFlag.create_boolean_feature_flag(name, true)

    @cache
      .expects(:get)
      .with(get_feature_flag_cache_key(name))
      .returns(cached_flag)

    response = @test_service.get(
      name,
      fetch_directly_from_adapter: false,
      cache_without_expiry: false,
      _allow_context_overrides: false,
      instrumentation_context: @instrumentation_context
    )

    assert_equal cached_flag, response
    assert_equal({
      "feature_flag.memoization.fetch": {
        entities_count: 0,
      },
      "feature_flag.cache.fetch": {
        measured_start: time,
        measured_finish: time,
        entities_count: 1,
      },
    }, @instrumentation_context.to_h)
  end

  def test_get_from_cache_with_circuit_breakers
    time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    Process.stubs(:clock_gettime).with(Process::CLOCK_MONOTONIC).returns(time)

    cached_flag = Vexi::FeatureFlag.create_boolean_feature_flag("feature1", true)

    name = "feature1"

    @cache
      .expects(:get)
      .with(get_feature_flag_cache_key(name))
      .returns(cached_flag)

    response = @test_service_with_breakers.get(
      name,
      fetch_directly_from_adapter: false,
      cache_without_expiry: false,
      _allow_context_overrides: false,
      instrumentation_context: @instrumentation_context,
    )

    assert_equal cached_flag, response
    assert_equal({
      "feature_flag.memoization.fetch": {
        entities_count: 0,
      },
      "feature_flag.cache.fetch": {
        measured_start: time,
        measured_finish: time,
        entities_count: 1,
      },
    }, @instrumentation_context.to_h)
  end

  def test_get_from_adapter
    time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    Process.stubs(:clock_gettime).with(Process::CLOCK_MONOTONIC).returns(time)

    name = "feature1"

    adapter_flag = Vexi::FeatureFlag.create_boolean_feature_flag(name, true)
    adapter_response = [
      Vexi::GetFeatureFlagResponse.new(name: adapter_flag.name, feature_flag: adapter_flag, error: nil)
    ]

    @adapter
      .expects(:get_feature_flags)
      .with([adapter_flag.name])
      .returns(adapter_response)
    cache_key = get_feature_flag_cache_key(name)
    @cache
      .expects(:get)
      .with(get_feature_flag_cache_key(name))
      .returns(nil)
    @cache
      .expects(:set)
      .with(cache_key, adapter_flag, @cache_config.ttl)

    response = @test_service.get(
      name,
      fetch_directly_from_adapter: false,
      cache_without_expiry: false,
      _allow_context_overrides: false,
      instrumentation_context: @instrumentation_context,
    )

    assert_equal adapter_flag, response
    assert_equal({
      "feature_flag.memoization.fetch": {
        entities_count: 0,
      },
      "feature_flag.cache.fetch": {
        measured_start: time,
        measured_finish: time,
        entities_count: 0,
      },
      "feature_flag.adapter.fetch": {
        measured_start: time,
        measured_finish: time,
        entities_count: 1,
      },
    }, @instrumentation_context.to_h)
  end

  def test_get_from_adapter_with_circuit_breakers
    time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    Process.stubs(:clock_gettime).with(Process::CLOCK_MONOTONIC).returns(time)

    name = "feature1"
    adapter_flag = Vexi::FeatureFlag.create_boolean_feature_flag(name, true)
    adapter_response = [
      Vexi::GetFeatureFlagResponse.new(name: adapter_flag.name, feature_flag: adapter_flag, error: nil)
    ]

    @adapter
      .expects(:get_feature_flags)
      .with([adapter_flag.name])
      .returns(adapter_response)
    cache_key = get_feature_flag_cache_key(name)
    @cache
      .expects(:get)
      .with(get_feature_flag_cache_key(name))
      .returns(nil)
    @cache
      .expects(:set)
      .with(cache_key, adapter_flag, @cache_config.ttl)

    response = @test_service_with_breakers.get(
      name,
      fetch_directly_from_adapter: false,
      cache_without_expiry: false,
      _allow_context_overrides: false,
      instrumentation_context: @instrumentation_context,
    )

    assert_equal adapter_flag, response
    assert_equal({
      "feature_flag.memoization.fetch": {
        entities_count: 0,
      },
      "feature_flag.cache.fetch": {
        measured_start: time,
        measured_finish: time,
        entities_count: 0,
      },
      "feature_flag.adapter.fetch": {
        measured_start: time,
        measured_finish: time,
        entities_count: 1,
      },
    }, @instrumentation_context.to_h)
  end

  def test_get_from_cache_with_exceptions
    time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    Process.stubs(:clock_gettime).with(Process::CLOCK_MONOTONIC).returns(time)

    name = "feature1"
    adapter_flag = Vexi::FeatureFlag.create_boolean_feature_flag(name, true)
    adapter_response = [
      Vexi::GetFeatureFlagResponse.new(name: adapter_flag.name, feature_flag: adapter_flag, error: nil)
    ]

    @adapter
      .expects(:get_feature_flags)
      .with([adapter_flag.name])
      .returns(adapter_response)

    error = StandardError.new("Boom!")

    cache_key = get_feature_flag_cache_key(name)
    @cache
      .expects(:get)
      .with(get_feature_flag_cache_key(name))
      .raises(error)
    @cache
      .expects(:set)
      .with(cache_key, adapter_flag, @cache_config.ttl)
      .raises(error)

    response = @test_service.get(
      name,
      fetch_directly_from_adapter: false,
      cache_without_expiry: false,
      _allow_context_overrides: false,
      instrumentation_context: @instrumentation_context
    )

    assert_equal adapter_flag, response
    assert_equal({
      "feature_flag.memoization.fetch": {
        entities_count: 0,
      },
      "feature_flag.cache.fetch": {
        measured_start: time,
        measured_finish: time,
      },
      "feature_flag.cache.fetch.error": {
        error: error,
        message: "Error fetching entity from cache",
      },
      "feature_flag.cache.set.error": {
        error: error,
        message: "Error setting entity in cache",
      },
      "feature_flag.adapter.fetch": {
        measured_start: time,
        measured_finish: time,
        entities_count: 1,
      },
    }, @instrumentation_context.to_h)
  end

  def test_get_from_adapter_caches_not_found_from_empty_response
    time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    Process.stubs(:clock_gettime).with(Process::CLOCK_MONOTONIC).returns(time)

    name = "feature1"

    default_flag = @test_service.get_default_entity_instance("feature1")

    @adapter
      .expects(:get_feature_flags)
      .with([name])
      .returns([])
    cache_key = get_feature_flag_cache_key(name)
    @cache
      .expects(:get)
      .with(get_feature_flag_cache_key(name))
      .returns(nil)
    @cache
      .expects(:set)
      .with(cache_key, default_flag, @cache_config.not_found_ttl)

    response = @test_service.get(
      name,
      fetch_directly_from_adapter: false,
      cache_without_expiry: false,
      _allow_context_overrides: false,
      instrumentation_context: @instrumentation_context,
    )

    assert_equal default_flag, response
    assert_equal({
      "feature_flag.memoization.fetch": {
        entities_count: 0,
      },
      "feature_flag.cache.fetch": {
        measured_start: time,
        measured_finish: time,
        entities_count: 0,
      },
      "feature_flag.adapter.fetch": {
        measured_start: time,
        measured_finish: time,
        entities_count: 1,
      },
    }, @instrumentation_context.to_h)
  end

  def test_get_from_adapter_caches_not_found_from_not_found_response
    time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    Process.stubs(:clock_gettime).with(Process::CLOCK_MONOTONIC).returns(time)

    name = "feature1"

    default_flag = @test_service.get_default_entity_instance("feature1")

    @adapter
      .expects(:get_feature_flags)
      .with([name])
      .returns([Vexi::GetFeatureFlagResponse.new(name: name, feature_flag: nil, error: Vexi::Errors::FeatureFlagNotFoundError.new(name))])
    cache_key = get_feature_flag_cache_key(name)
    @cache
      .expects(:get)
      .with(get_feature_flag_cache_key(name))
      .returns(nil)
    @cache
      .expects(:set)
      .with(cache_key, default_flag, @cache_config.not_found_ttl)

    response = @test_service.get(
      name,
      fetch_directly_from_adapter: false,
      cache_without_expiry: false,
      _allow_context_overrides: false,
      instrumentation_context: @instrumentation_context,
    )

    assert_equal default_flag, response
    assert_equal({
      "feature_flag.memoization.fetch": {
        entities_count: 0,
      },
      "feature_flag.cache.fetch": {
        measured_start: time,
        measured_finish: time,
        entities_count: 0,
      },
      "feature_flag.adapter.fetch": {
        measured_start: time,
        measured_finish: time,
        entities_count: 1,
      },
    }, @instrumentation_context.to_h)
  end

  def test_get_fetch_directly_from_adapter
    time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    Process.stubs(:clock_gettime).with(Process::CLOCK_MONOTONIC).returns(time)

    name = "feature1"

    adapter_flag = Vexi::FeatureFlag.create_boolean_feature_flag(name, true)
    adapter_response = [
      Vexi::GetFeatureFlagResponse.new(name: adapter_flag.name, feature_flag: adapter_flag, error: nil)
    ]

    @adapter
      .expects(:get_feature_flags)
      .with([adapter_flag.name])
      .returns(adapter_response)
    cache_key = get_feature_flag_cache_key(name)
    @cache
      .expects(:set)
      .with(cache_key, adapter_flag, @cache_config.ttl)

    response = @test_service.get(
      name,
      fetch_directly_from_adapter: true,
      cache_without_expiry: false,
      _allow_context_overrides: false,
      instrumentation_context: @instrumentation_context,
    )

    assert_equal adapter_flag, response
    assert_equal({
      "feature_flag.memoization.fetch": {
        entities_count: 0,
      },
      "feature_flag.cache.fetch": {
        measured_start: time,
        measured_finish: time,
        entities_count: 0,
      },
      "feature_flag.adapter.fetch": {
        measured_start: time,
        measured_finish: time,
        entities_count: 1,
      },
    }, @instrumentation_context.to_h)
  end

  def test_get_from_adapter_cache_without_expiry
    time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    Process.stubs(:clock_gettime).with(Process::CLOCK_MONOTONIC).returns(time)

    name = "feature1"

    adapter_flag = Vexi::FeatureFlag.create_boolean_feature_flag(name, true)
    adapter_response = [
      Vexi::GetFeatureFlagResponse.new(name: adapter_flag.name, feature_flag: adapter_flag, error: nil)
    ]

    @adapter
      .expects(:get_feature_flags)
      .with([adapter_flag.name])
      .returns(adapter_response)
    cache_key = get_feature_flag_cache_key(name)
    @cache
      .expects(:get)
      .with(get_feature_flag_cache_key(name))
      .returns(nil)
    @cache
      .expects(:set)
      .with(cache_key, adapter_flag, Vexi::Cache::TTL_NEVER_EXPIRE)

    response = @test_service.get(
      name,
      fetch_directly_from_adapter: false,
      cache_without_expiry: true,
      _allow_context_overrides: false,
      instrumentation_context: @instrumentation_context,
    )

    assert_equal adapter_flag, response
    assert_equal({
      "feature_flag.memoization.fetch": {
        entities_count: 0,
      },
      "feature_flag.cache.fetch": {
        measured_start: time,
        measured_finish: time,
        entities_count: 0,
      },
      "feature_flag.adapter.fetch": {
        measured_start: time,
        measured_finish: time,
        entities_count: 1,
      },
    }, @instrumentation_context.to_h)
  end

  private

  def get_feature_flag_cache_key(name)
    "vexi:ff:#{name}"
  end
end
