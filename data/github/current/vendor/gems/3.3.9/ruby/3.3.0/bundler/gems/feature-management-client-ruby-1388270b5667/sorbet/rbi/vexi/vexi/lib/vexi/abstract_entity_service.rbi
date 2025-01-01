# frozen_string_literal: true
# typed: strict

module Vexi
  # Public: Vexi service is an abstract base class. It has a generic get to fetch entities from the adapter or cache.
  class AbstractEntityService
    extend T::Sig
    extend T::Helpers
    extend T::Generic # Provides `type_member` helper
    abstract!

    include Kernel

    sig {
      params(
        adapter: Adapter,
        cache_config: T.nilable(CacheConfig),
        adapter_breaker: T.nilable(Resilient::CircuitBreaker),
        cache_breaker: T.nilable(Resilient::CircuitBreaker)
      ).void
    }
    def initialize(adapter, cache_config = nil, adapter_breaker = nil, cache_breaker = nil); end

    sig { abstract.returns(T::Class[EntityType]) }
    def entity_type; end

    sig { abstract.returns(String) }
    def entity_type_name; end

    sig { params(value: T::Boolean).void }
    def memoize=(value); end

    sig do
      params(
        name: String,
        fetch_directly_from_adapter: T::Boolean,
        cache_without_expiry: T::Boolean,
        raise_on_cache_breaker_open: T::Boolean,
        _allow_context_overrides: T::Boolean,
        instrumentation_context: InstrumentationContext,
      ).returns(T.nilable(EntityType))
    end
    def get(name, fetch_directly_from_adapter: false, cache_without_expiry: false, raise_on_cache_breaker_open: true, _allow_context_overrides: false, instrumentation_context: InstrumentationContext.new); end

    sig do
      params(
        names: T::Array[String],
        fetch_directly_from_adapter: T::Boolean,
        cache_without_expiry: T::Boolean,
        raise_on_cache_breaker_open: T::Boolean,
        _allow_context_overrides: T::Boolean,
        instrumentation_context: InstrumentationContext,
      ).returns(T::Array[EntityType])
    end
    def mget(names, fetch_directly_from_adapter: false, cache_without_expiry: false, raise_on_cache_breaker_open: true, _allow_context_overrides: false, instrumentation_context: InstrumentationContext.new); end

    private

    sig { abstract.params(name: String).returns(String) }
    def get_cache_key(name); end

    sig { abstract.params(names: T::Array[String]).returns(T::Array[GetEntityResponse]) }
    def get_entity_responses(names); end

    sig { abstract.params(name: String).returns(EntityType) }
    def get_default_entity_instance(name); end

    sig { params(names: T::Array[String]).returns(T::Array[String]) }
    def get_cache_keys(names); end

    sig { params(entity_names: T::Array[String], fetch_directly_from_adapter: T::Boolean).returns(T::Array[EntityType]) }
    def get_entities_from_memoization(entity_names, fetch_directly_from_adapter); end

    sig { params(entity_name: String, fetch_directly_from_adapter: T::Boolean).returns(T.nilable(EntityType)) }
    def get_entity_from_memoization(entity_name, fetch_directly_from_adapter); end

    sig { params(entity_names: T::Array[String], fetch_directly_from_adapter: T::Boolean, instrumentation_context: InstrumentationContext).returns(T::Array[EntityType]) }
    def get_entities_from_cache(entity_names, fetch_directly_from_adapter, instrumentation_context); end

    sig { params(entity_name: String, fetch_directly_from_adapter: T::Boolean, instrumentation_context: InstrumentationContext).returns(T.nilable(EntityType)) }
    def get_entity_from_cache(entity_name, fetch_directly_from_adapter, instrumentation_context); end

    sig { params(entity_names: T::Array[String], cache_without_expiry: T::Boolean, instrumentation_context: InstrumentationContext).returns(T::Array[EntityType]) }
    def get_entities_from_adapter(entity_names, cache_without_expiry, instrumentation_context); end

    sig { params(entity_name: String, cache_without_expiry: T::Boolean, instrumentation_context: InstrumentationContext).returns(EntityType) }
    def get_entity_from_adapter(entity_name, cache_without_expiry, instrumentation_context); end

    sig { params(breaker: T.nilable(Resilient::CircuitBreaker), instrumentation_context: InstrumentationContext, operation: String, block: T.proc.void).void }
    def circuit_breaker_run(breaker, instrumentation_context, operation, &block); end
  end
end
