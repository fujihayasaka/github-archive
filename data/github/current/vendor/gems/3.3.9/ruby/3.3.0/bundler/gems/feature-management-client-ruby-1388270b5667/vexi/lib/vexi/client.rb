# frozen_string_literal: true
# typed: strict

require "sorbet-runtime"
require "vexi/abstract_entity_service"
require "vexi/actor"
require "vexi/adapter"
require "vexi/cache"
require "vexi/cache_config"
require "vexi/custom_gates_evaluator"
require "vexi/errors"
require "vexi/models/feature_flag"
require "vexi/models/get_entity_response"
require "vexi/models/get_feature_flag_response"
require "vexi/models/get_segment_response"
require "vexi/models/segment"
require "vexi/non_actor_gate_evaluator"
require "vexi/notifications"
require "vexi/services/feature_flag_service"
require "vexi/services/segment_service"

module Vexi
    # Public: The main Vexi class for performing feature flag enabled checks.
  class Client
    def initialize(config, feature_flag_service, segment_service)
      @memoization_enabled = T.let(false, T::Boolean)

      @config = T.let(config, Configuration)
      @feature_flag_service = T.let(feature_flag_service, Vexi::Services::FeatureFlagService)
      @segment_service = T.let(segment_service, Vexi::Services::SegmentService)
      @cache_config = T.let(config.cache_config, T.nilable(CacheConfig))
      @fallback_evaluator = T.let(config.fallback_evaluator, Configuration::FallbackEvaluator)
      @custom_gate_evaluator = T.let(config.custom_gates_evaluator, T.nilable(CustomGatesEvaluator))

      Notifications.configuration_context = configuration_context
      Notifications.configuration_context[:memoization_enabled] = memoizing?
    end

    def enabled?(name, *actors)
      Notifications.instrument_timing("is_enabled", properties: { feature_flag_name: name, number_of_actors_being_checked: actors.size }) do |instrumentation_context|
        name = name.to_s
        result = enabled_internal?(name, actors, instrumentation_context)
        instrumentation_context[:result] = result
        result
      end
    end

    def memoize=(value)
      @feature_flag_service.memoize = value
      @segment_service.memoize = value
      @memoization_enabled = value
      Notifications.configuration_context[:memoization_enabled] = value
    end

    def memoizing?
      !!@memoization_enabled
    end

    # Preload the named feature flags and any related segments into the cache and/or memoization layer.
    # fetch_directly_from_adapter (default: true)
    #   If true, fetch the data directly from the adapter and replace any existing values in the cache.
    #   Use false to only fetch from the adapter on cache miss, but not to replace existing values in the cache. This can be used for preloading from the cache into the memoization layer.
    # cache_without_expiry (default: false)
    #   If true, preloaded records will be stored in cache without expiry.
    #      Use this along with a cache that has a TTL to ensure that preloaded records never expire (this assumes you have a separate process for updating the cache or calling preload).
    #      This enables any non-preloaded feature flags checked via enabled? calls to use the configured TTL for expiry.
    #   If false, preloaded records will be stored in the cache with the TTL configured along with the cache.
    # instrumentation_properties (default: {})
    #   If provided, allows to attach custom values to instrumentation context. These values will be attached to the instrumentation event fired when the preload is done.
    def preload(names, fetch_directly_from_adapter: true, cache_without_expiry: false, instrumentation_properties: {})
      Notifications.instrument_timing("preload", properties: { feature_flag_names: names, fetch_directly_from_adapter: fetch_directly_from_adapter, **instrumentation_properties }) do |instrumentation_context|
        result = preload_internal(names, fetch_directly_from_adapter, cache_without_expiry, instrumentation_context)
        instrumentation_context[:result] = result
        result
      end
    end

    def configuration_context
      @config.context
    end

    def enabled_internal?(name, actors, instrumentation_context)
      exception_occurred = false

      begin
        feature_flag = @feature_flag_service.get(
          name,
          fetch_directly_from_adapter: false,
          cache_without_expiry: false,
          raise_on_cache_breaker_open: true,
          instrumentation_context: instrumentation_context,
        )
      rescue StandardError => e
        instrumentation_context.instrument_error(:"feature_flag.adapter.error", e, message: "error getting feature flag")
        return call_fallback_evaluator(name, actors, instrumentation_context)
      end

      return false unless feature_flag
      return true if NonActorGateEvaluator.evaluate_boolean_gate(feature_flag)
      return true if NonActorGateEvaluator.evaluate_percentage_of_calls(feature_flag)

      actor_ids = []
      nil_actor_indices = []
      invalid_actor_type_indices = []

      actors.each_with_index do |actor, index|
        if actor.nil?
          nil_actor_indices << index
          next
        elsif actor.is_a?(String)
          actor_ids << actor
        elsif actor.respond_to?(:vexi_id)
          actor_ids << T.unsafe(actor.vexi_id)
        elsif actor.is_a?(Actor)
          actor_ids << actor.vexi_id
        else
          invalid_actor_type_indices << index
          next
        end
      end

      if nil_actor_indices.any?
        instrumentation_context[:nil_actor_indices] = nil_actor_indices
      end

      if invalid_actor_type_indices.any?
        instrumentation_context[:invalid_actor_type_indices] = invalid_actor_type_indices
      end

      return true if NonActorGateEvaluator.evaluate_percentage_of_actors(feature_flag, actor_ids)
      return true if NonActorGateEvaluator.evaluate_embedded_actors(feature_flag.actors, actor_ids)

      segments = T.let([], T::Array[Segment])
      begin
        segments = @segment_service.mget(
          feature_flag.segments,
          fetch_directly_from_adapter: false,
          cache_without_expiry: false,
          raise_on_cache_breaker_open: true,
          instrumentation_context: instrumentation_context,
        )
      rescue StandardError => e
        instrumentation_context.instrument_error(:"segment.adapter.error", e, message: "error getting segments", properties: { segment_names: feature_flag.segments })
        exception_occurred = true
      end

      return true if segments.any? do |segment|
        return true if NonActorGateEvaluator.evaluate_embedded_actors(segment.actors, actor_ids)
      end

      begin
        # If the custom gates evaluator is not set, we will silently ignore the custom gates even if they are present.
        if feature_flag.custom_gates.any? && @custom_gate_evaluator
          instrumentation_context.instrument_timing(:custom_gates) do |properties|
            result = @custom_gate_evaluator.enabled?(feature_flag.name, feature_flag.custom_gates, actors)
            properties[:result] = result
            return true if result
          end
        end
      rescue StandardError => e
        instrumentation_context.instrument_error(:"custom_gate_evaluator.error", e, message: "error evaluating custom gates")
        exception_occurred = true
      end

      if exception_occurred
        return call_fallback_evaluator(name, actors, instrumentation_context)
      end

      false
    end

    def call_fallback_evaluator(name, actors, instrumentation_context)
      instrumentation_context.instrument_timing(:fallback_evaluator) do |properties|
        result = @fallback_evaluator.call(name, actors)
        properties[:result] = result
        result
      end
    end

    def preload_internal(names, fetch_directly_from_adapter, cache_without_expiry, instrumentation_context)
      raise Errors::ValidationError, "Preloading requires at least one named feature flag to load" if names.empty?
      raise Errors::ValidationError, "Preloading is not supported without a cache configured or memoizing enabled" if @cache_config.nil? && !memoizing?

      begin
        feature_flags = @feature_flag_service.mget(
          names.map(&:to_s),
          fetch_directly_from_adapter: fetch_directly_from_adapter,
          cache_without_expiry: cache_without_expiry,
          raise_on_cache_breaker_open: false,
          instrumentation_context: instrumentation_context,
        )
      rescue StandardError => e
        instrumentation_context.instrument_error(:"feature_flag.adapter.error", e, message: "error getting feature flags")
        return false
      end

      segment_names = T.let([], T::Array[String])
      feature_flags.each do |feature_flag|
        segment_names.concat(feature_flag.segments)
      end
      segment_names.uniq!

      begin
        @segment_service.mget(
          segment_names,
          fetch_directly_from_adapter: fetch_directly_from_adapter,
          cache_without_expiry: false,
          raise_on_cache_breaker_open: false,
          instrumentation_context: instrumentation_context,
        ) unless segment_names.empty?
      rescue StandardError => e
        instrumentation_context.instrument_error(:"segment.adapter.error", e, message: "error getting segments", properties: { segment_names: segment_names })
        return false
      end

      true
    end
  end
end
