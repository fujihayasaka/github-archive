# frozen_string_literal: true
# typed: strict

module Vexi
    # Public: The main Vexi class for performing feature flag enabled checks.
  class Client
    extend T::Sig

    sig do
      params(
        config: Configuration,
        feature_flag_service: Services::FeatureFlagService,
        segment_service: Services::SegmentService,
      ).void
    end
    def initialize(config, feature_flag_service, segment_service); end

    sig { params(name: T.any(String, Symbol), actors: T.any(Actor, String)).returns(T::Boolean) }
    def enabled?(name, *actors); end

    sig { params(value: T::Boolean).void }
    def memoize=(value); end

    sig { returns(T::Boolean) }
    def memoizing?; end

    # Preload the named feature flags and any related segments into the cache and/or memoization layer.
    # fetch_directly_from_adapter (default: true)
    #   If true, fetch the data directly from the adapter and replace any existing values in the cache.
    #   Use false to only fetch from the adapter on cache miss, but not to replace existing values in the cache. This can be used for preloading from the cache into the memoization layer.
    # cache_without_expiry (default: false)
    #   If true, preloaded records will be stored in cache without expiry.
    #      Use this along with a cache that has a TTL to ensure that preloaded records never expire (this assumes you have a separate process for updating the cache or calling preload).
    #      This enables any non-preloaded feature flags checked via enabled? calls to use the configured TTL for expiry.
    #   If false, preloaded records will be stored in the cache with the TTL configured along with the cache.
    sig { params(names: T::Array[T.any(String, Symbol)], fetch_directly_from_adapter: T::Boolean, cache_without_expiry: T::Boolean, instrumentation_properties: Instrumenter::NotificationContext).void }
    def preload(names, fetch_directly_from_adapter: true, cache_without_expiry: false, instrumentation_properties: {}); end

    sig { returns(T::Hash[Symbol, String]) }
    def configuration_context; end

    private

    sig { params(name: String, actors: T::Array[T.any(Actor, String)], instrumentation_context: InstrumentationContext).returns(T::Boolean) }
    def enabled_internal?(name, actors, instrumentation_context); end

    sig { params(name: String, actors: T::Array[T.any(Actor, String)], instrumentation_context: InstrumentationContext).returns(T::Boolean) }
    def call_fallback_evaluator(name, actors, instrumentation_context); end

    sig { params(names: T::Array[T.any(String, Symbol)], fetch_directly_from_adapter: T::Boolean, cache_without_expiry: T::Boolean, instrumentation_context: InstrumentationContext).returns(T::Boolean) }
    def preload_internal(names, fetch_directly_from_adapter, cache_without_expiry, instrumentation_context); end
  end
end
