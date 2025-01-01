# frozen_string_literal: true
#              


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
    def initialize(config, feature_flag_service, segment_service, notifications)
      @memoization_enabled =      (false            )

      @config =      (config               )
      @feature_flag_service =      (feature_flag_service                                    )
      @segment_service =      (segment_service                                )
      @cache_config =      (config.cache_config                        )
      @custom_gate_evaluator =      (config.custom_gates_evaluator                                 )
      @notifications =      (notifications               )

      @notifications.configuration_context[:memoization_enabled] = memoizing?
    end

    def enabled?(name, *actors, default:)
      raise_on_error = false
      name = name.to_s.downcase

      @notifications.instrument_timing("is_enabled", properties: { feature_flag_name: name, number_of_actors_being_checked: actors.size, default_value: default, raise_on_error: raise_on_error }) do |instrumentation_context|
        result = enabled_internal?(name, actors, default, instrumentation_context, raise_on_error)
        instrumentation_context[:result] = result
        result
      end
    end

    def unsafe_enabled?(name, *actors)
      default = false
      raise_on_error = true
      name = name.to_s.downcase

      @notifications.instrument_timing("is_enabled", properties: { feature_flag_name: name, number_of_actors_being_checked: actors.size, default_value: default, raise_on_error: raise_on_error }) do |instrumentation_context|
        result = enabled_internal?(name, actors, default, instrumentation_context, raise_on_error)
        instrumentation_context[:result] = result
        result
      end
    end

    def memoize=(value)
      @feature_flag_service.memoize = value
      @segment_service.memoize = value
      @memoization_enabled = value
      @notifications.configuration_context[:memoization_enabled] = value
    end

    def memoizing?
      !!@memoization_enabled
    end

    def configuration_context
      @notifications.configuration_context
    end

    # Override one or more features. Features matching the passed-in pattern will be temporarily enabled or disabled until clear_overrides is called.
    #
    # pattern - A fnmatch-style pattern to match feature names against.
    # enabled - A Boolean specifying whether the features should be enabled (true) or disabled (false).
    def add_override(pattern, enabled:)
      overrides[pattern.to_s] = enabled
    end

    # Remove all feature overrides.
    def clear_overrides
      overrides.clear
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
      raise_on_error = false
      names = names.map { |name| name.to_s.downcase }

      @notifications.instrument_timing("preload", properties: { feature_flag_names: names, fetch_directly_from_adapter: fetch_directly_from_adapter, raise_on_error: raise_on_error, **instrumentation_properties }) do |instrumentation_context|
        result = preload_internal(names, fetch_directly_from_adapter, cache_without_expiry, raise_on_error, instrumentation_context)
        instrumentation_context[:result] = result
        result
      end
    end

    # Preload the named feature flags and any related segments into the cache and/or memoization layer.
    # This version of the preload method will raise an error if an error occurs while preloading.
    def unsafe_preload(names, fetch_directly_from_adapter: true, cache_without_expiry: false, instrumentation_properties: {})
      raise_on_error = true
      names = names.map { |name| name.to_s.downcase }

      @notifications.instrument_timing("preload", properties: { feature_flag_names: names, fetch_directly_from_adapter: fetch_directly_from_adapter, raise_on_error: raise_on_error, **instrumentation_properties }) do |instrumentation_context|
        result = preload_internal(names, fetch_directly_from_adapter, cache_without_expiry, raise_on_error, instrumentation_context)
        instrumentation_context[:result] = result
        result
      end
    end

    private

    def overrides
      Thread.current[:vexi_overrides] ||= {}
    end

    def enabled_internal?(name, actors, default_value, instrumentation_context, raise_on_error)
      begin
        _, override_value = overrides.find { |key, value| File.fnmatch?(key, name.to_s) }
        if !override_value.nil?
          instrumentation_context[:result_reason] = "override"
          return override_value
        end

        feature_flag = @feature_flag_service.get(
          name,
          fetch_directly_from_adapter: false,
          cache_without_expiry: false,
          raise_on_cache_breaker_open: true,
          instrumentation_context: instrumentation_context,
        )
      rescue StandardError => e
        instrumentation_context.instrument_error(:"feature_flag.adapter.error", e, message: "error getting feature flag")
        instrumentation_context[:evaluation_unsuccessful] = true

        raise if raise_on_error

        instrumentation_context[:responded_with_default_value] = true
        instrumentation_context[:result_reason] = "error"
        return default_value
      end

      if feature_flag.nil? || feature_flag.not_found
        instrumentation_context[:result_reason] = "not_found"
        return false
      end

      if NonActorGateEvaluator.evaluate_boolean_gate(feature_flag)
        instrumentation_context[:result_reason] = "fully_enabled"
        return true
      end
      if NonActorGateEvaluator.evaluate_percentage_of_calls(feature_flag)
        instrumentation_context[:result_reason] = "percentage_of_calls"
        return true
      end

      actor_ids = []
      nil_actor_indices = []
      invalid_actor_type_indices = []
      only_flipper_actor_indices = []

      actors.each_with_index do |actor, index|
        if actor.nil?
          nil_actor_indices << index
          next
        elsif actor.is_a?(String)
          actor_ids << actor
        elsif actor.respond_to?(:vexi_id)
          actor_ids << actor.vexi_id
        elsif actor.respond_to?(:flipper_id)
          actor_ids <<         (actor).flipper_id
          only_flipper_actor_indices << index
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

      if only_flipper_actor_indices.any?
        instrumentation_context[:only_flipper_actor_indices] = only_flipper_actor_indices
      end

      if NonActorGateEvaluator.evaluate_percentage_of_actors(feature_flag, actor_ids)
        instrumentation_context[:result_reason] = "percentage_of_actors"
        return true
      end

      if NonActorGateEvaluator.evaluate_embedded_actors(feature_flag.actors, actor_ids)
        instrumentation_context[:result_reason] = "actor_match"
        return true
      end

      segments =      ([]                   )
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

        if raise_on_error
          instrumentation_context[:evaluation_unsuccessful] = true
          raise
        end

        error_occurred = true
      end

      return true if segments.any? do |segment|
        if NonActorGateEvaluator.evaluate_embedded_actors(segment.actors, actor_ids)
          instrumentation_context[:result_reason] = "actor_match"
          next true
        end
      end

      begin
        # If the custom gates evaluator is not set, we will silently ignore the custom gates even if they are present.
        if feature_flag.custom_gates.any? && @custom_gate_evaluator
          instrumentation_context.instrument_timing(:custom_gates) do |properties|
            result = @custom_gate_evaluator.enabled?(feature_flag.name, feature_flag.custom_gates, actors)
            properties[:result] = result
            if result
              instrumentation_context[:result_reason] = "custom_gate"
              return true
            end
          end
        end
      rescue StandardError => e
        instrumentation_context.instrument_error(:"custom_gate_evaluator.error", e, message: "error evaluating custom gates")

        if raise_on_error
          instrumentation_context[:evaluation_unsuccessful] = true
          raise
        end

        error_occurred = true
      end

      if error_occurred
        instrumentation_context[:evaluation_unsuccessful] = true
        instrumentation_context[:responded_with_default_value] = true
        instrumentation_context[:result_reason] = "error"
        return default_value
      end

      instrumentation_context[:result_reason] = "all_checks_false"
      false
    end

    def preload_internal(names, fetch_directly_from_adapter, cache_without_expiry, raise_on_error, instrumentation_context)
      raise Errors::ValidationError, "Preloading requires at least one named feature flag to load" if names.empty?
      raise Errors::ValidationError, "Preloading is not supported without a cache configured or memoizing enabled" if @cache_config.nil? && !memoizing?

      begin
        feature_flags = @feature_flag_service.mget(
          names,
          fetch_directly_from_adapter: fetch_directly_from_adapter,
          cache_without_expiry: cache_without_expiry,
          raise_on_cache_breaker_open: false,
          instrumentation_context: instrumentation_context,
        )
      rescue StandardError => e
        instrumentation_context.instrument_error(:"feature_flag.adapter.error", e, message: "error getting feature flags")
        instrumentation_context[:evaluation_unsuccessful] = true

        raise if raise_on_error

        return false
      end

      segment_names =      ([]                  )
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
        instrumentation_context[:evaluation_unsuccessful] = true

        raise if raise_on_error

        return false
      end

      true
    end
  end
end
