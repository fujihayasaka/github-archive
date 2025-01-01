# frozen_string_literal: true
#              


require "vexi/abstract_entity_service"
require "vexi/actor"
require "vexi/adapter"
require "vexi/cache"
require "vexi/cache_config"
require "vexi/custom_gates_evaluator"
require "vexi/errors"
require "vexi/evaluation_details"
require "vexi/models/feature_flag"
require "vexi/models/get_entity_response"
require "vexi/models/get_feature_flag_response"
require "vexi/models/get_segment_response"
require "vexi/models/segment"
require "vexi/notifications"
require "vexi/result_reason"
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

    # Determine if a feature is enabled. Returns an evaluation details object containing value, reason, and error (if any).
    #
    # name
    #   The name of the feature flag.
    # actors (optional)
    #   One or more actors to check against the feature flag.
    #   If the feature flag is enabled for any of the provided actors, the method will return true.
    # default:
    #  The default value to return if the feature flag is not found or an error occurs while evaluating the feature flag state.
    def enabled_with_details(name, *actors, default:)
      name = name.to_s.downcase
      actors = flatten_actors(actors) if actors

      @notifications.instrument_timing("is_enabled", properties: { feature_flag_name: name, number_of_actors_being_checked: actors.size, default_value: default, method: "enabled_with_details" }) do |instrumentation_context|
        details = enabled_internal(name, actors, default, instrumentation_context)
        instrument_evaluation_details(instrumentation_context, details)
        details
      end
    end

    # Determine if a feature is enabled. Returns a boolean value.
    #
    # name
    #   The name of the feature flag.
    # actors (optional)
    #   One or more actors to check against the feature flag.
    #   If the feature flag is enabled for any of the provided actors, the method will return true.
    # default:
    #  The default value to return if the feature flag is not found or an error occurs while evaluating the feature flag state.
    def enabled?(name, *actors, default:)
      name = name.to_s.downcase
      actors = flatten_actors(actors) if actors

      @notifications.instrument_timing("is_enabled", properties: { feature_flag_name: name, number_of_actors_being_checked: actors.size, default_value: default, method: "enabled" }) do |instrumentation_context|
        details = enabled_internal(name, actors, default, instrumentation_context)
        instrument_evaluation_details(instrumentation_context, details)
        details.result
      end
    end

    # Determine if a feature is enabled. Returns a boolean value. Raises if an error occurs while evaluating feature flag state.
    #
    # name
    #   The name of the feature flag.
    # actors (optional)
    #   One or more actors to check against the feature flag.
    #   If the feature flag is enabled for any of the provided actors, the method will return true.
    def enabled_or_raise?(name, *actors)
      name = name.to_s.downcase
      actors = flatten_actors(actors) if actors
      default = false

      @notifications.instrument_timing("is_enabled", properties: { feature_flag_name: name, number_of_actors_being_checked: actors.size, default_value: default, method: "enabled_raise_on_error" }) do |instrumentation_context|
        details = enabled_internal(name, actors, default, instrumentation_context)
        instrument_evaluation_details(instrumentation_context, details)
        instrumentation_context[:responded_with_default_value] = false # this method never responds with the default value, so ensure this is set to false
        raise       (details.error) unless details.error.nil?
        details.result
      end
    end

    # NOTE: This method is only there for compatibility with the old Flipper API.
    # It is not recommended to use this method in new code.
    #
    # Get a list of raw actors that are enabled for the feature flag.
    # Returns an empty array if the feature flag is not found.
    #
    # name
    #   The name of the feature flag.
    def actors_value_or_raise(name)
      name = name.to_s.downcase

      @notifications.instrument_timing("actors_value", properties: { feature_flag_name: name }) do |instrumentation_context|
        feature_flag = get_flag_details_or_raise(name, instrumentation_context)

        if feature_flag.nil? || feature_flag.not_found
          instrumentation_context[:result_reason] = ResultReason::NOT_FOUND
          return []
        end

        instrumentation_context[:result_reason] = ResultReason::ACTORS_VALUE
        feature_flag.actors.to_a
      end
    end

    # NOTE: This method is only there for compatibility with the old Flipper API.
    # It is not recommended to use this method in new code.
    #
    # Get the percentage of actors that the feature flag is enabled for.
    # Returns 0.0 if the feature flag is not found.
    #
    # name
    #   The name of the feature flag.
    def percentage_of_actors_value_or_raise(name)
      name = name.to_s.downcase

      @notifications.instrument_timing("percentage_of_actors_value", properties: { feature_flag_name: name }) do |instrumentation_context|
        feature_flag = get_flag_details_or_raise(name, instrumentation_context)

        if feature_flag.nil? || feature_flag.not_found
          instrumentation_context[:result_reason] = ResultReason::NOT_FOUND
          return 0.0
        end

        instrumentation_context[:result_reason] = ResultReason::PERCENTAGE_OF_ACTORS_VALUE
        feature_flag.percentage_of_actors
      end
    end

    # NOTE: This method is only there for compatibility with the old Flipper API.
    # It is not recommended to use this method in new code.
    #
    # Get the percentage of calls that the feature flag is enabled for.
    # Returns 0.0 if the feature flag is not found.
    #
    # name
    #   The name of the feature flag.
    def percentage_of_calls_value_or_raise(name)
      name = name.to_s.downcase

      @notifications.instrument_timing("percentage_of_calls_value", properties: { feature_flag_name: name }) do |instrumentation_context|
        feature_flag = get_flag_details_or_raise(name, instrumentation_context)

        if feature_flag.nil? || feature_flag.not_found
          instrumentation_context[:result_reason] = ResultReason::NOT_FOUND
          return 0.0
        end

        instrumentation_context[:result_reason] = ResultReason::PERCENTAGE_OF_CALLS_VALUE
        feature_flag.percentage_of_calls
      end
    end

    # NOTE: This method is only there for compatibility with the old Flipper API.
    # It is not recommended to use this method in new code.
    #
    # Check if a feature flag is fully enabled (boolean gate is true or it was enabled for 100% of calls).
    # Returns false if the feature flag is not found.
    #
    # name
    #   The name of the feature flag.
    def fully_enabled_or_raise?(name)
      name = name.to_s.downcase

      @notifications.instrument_timing("fully_enabled", properties: { feature_flag_name: name }) do |instrumentation_context|
        feature_flag = get_flag_details_or_raise(name, instrumentation_context)

        if feature_flag.nil? || feature_flag.not_found
          instrumentation_context[:result_reason] = ResultReason::NOT_FOUND
          return false
        end

        result = feature_flag.fully_enabled?
        instrumentation_context[:result] = result
        instrumentation_context[:result_reason] = result ? ResultReason::FULLY_ENABLED : ResultReason::NOT_FULLY_ENABLED
        result
      end
    end

    # NOTE: This method is only there for compatibility with the old Flipper API.
    # It is not recommended to use this method in new code.
    #
    # Check if a feature flag is fully disabled (no gates are active).
    # Returns true if the feature flag is not found.
    #
    # name
    #   The name of the feature flag.
    def fully_disabled_or_raise?(name)
      name = name.to_s.downcase

      @notifications.instrument_timing("fully_disabled", properties: { feature_flag_name: name }) do |instrumentation_context|
        feature_flag = get_flag_details_or_raise(name, instrumentation_context)

        if feature_flag.nil? || feature_flag.not_found
          instrumentation_context[:result_reason] = ResultReason::NOT_FOUND
          return true
        end

        result = feature_flag.fully_disabled?
        instrumentation_context[:result] = result
        instrumentation_context[:result_reason] = result ? ResultReason::FULLY_DISABLED : ResultReason::NOT_FULLY_DISABLED
        result
      end
    end

    # NOTE: This method is only there for compatibility with the old Flipper API.
    # It is not recommended to use this method in new code.
    #
    # Check if a feature flag exists.
    # Returns false if the feature flag is not found.
    #
    # name
    #   The name of the feature flag.
    def exists_or_raise?(name)
      name = name.to_s.downcase

      @notifications.instrument_timing("exists", properties: { feature_flag_name: name }) do |instrumentation_context|
        feature_flag = get_flag_details_or_raise(name, instrumentation_context)

        if feature_flag.nil? || feature_flag.not_found
          instrumentation_context[:result_reason] = ResultReason::NOT_FOUND
          return false
        end

        instrumentation_context[:result_reason] = ResultReason::EXISTS
        true
      end
    end

    # Enables or disables memoization.
    def memoize=(value)
      @feature_flag_service.memoize = value
      @segment_service.memoize = value
      @memoization_enabled = value
      @notifications.configuration_context[:memoization_enabled] = value
    end

    # Returns true if memoization is currently enabled, false otherwise.
    def memoizing?
      !!@memoization_enabled
    end

    # Clear the memoized values for a feature flag.
    def clear_feature_flag_memoization(name)
      name = name.to_s.downcase
      return if name.empty?

      @feature_flag_service.clear_memoized_entity_value(name)
      @segment_service.clear_memoized_entity_value(default_segment_name(name))
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
    # fetch_directly_from_adapter (default: false)
    #   If true, fetch the data directly from the adapter and replace any existing values in the cache.
    #   Use false to only fetch from the adapter on cache miss, but not to replace existing values in the cache. This can be used for preloading from the cache into the memoization layer.
    # cache_without_expiry (default: false)
    #   If true, preloaded records will be stored in cache without expiry.
    #      Use this along with a cache that has a TTL to ensure that preloaded records never expire (this assumes you have a separate process for updating the cache or calling preload).
    #      This enables any non-preloaded feature flags checked via enabled? calls to use the configured TTL for expiry.
    #   If false, preloaded records will be stored in the cache with the TTL configured along with the cache.
    # instrumentation_properties (default: {})
    #   If provided, allows to attach custom values to instrumentation context. These values will be attached to the instrumentation event fired when the preload is done.
    def preload(names, fetch_directly_from_adapter: false, cache_without_expiry: false, instrumentation_properties: {})
      raise_on_error = false
      names = names.map { |name| name.to_s.downcase }

      @notifications.instrument_timing("preload", properties: { feature_flag_names: names, fetch_directly_from_adapter: fetch_directly_from_adapter, method: "preload", **instrumentation_properties }) do |instrumentation_context|
        result = preload_internal(names, fetch_directly_from_adapter, cache_without_expiry, raise_on_error, instrumentation_context)
        instrumentation_context[:result] = result
        result
      end
    end

    # Preload the named feature flags and any related segments into the cache and/or memoization layer.
    # This version of the preload method will raise an error if an error occurs while preloading.
    def preload_or_raise(names, fetch_directly_from_adapter: false, cache_without_expiry: false, instrumentation_properties: {})
      raise_on_error = true
      names = names.map { |name| name.to_s.downcase }

      @notifications.instrument_timing("preload", properties: { feature_flag_names: names, fetch_directly_from_adapter: fetch_directly_from_adapter, method: "preload_raise_on_error", **instrumentation_properties }) do |instrumentation_context|
        result = preload_internal(names, fetch_directly_from_adapter, cache_without_expiry, raise_on_error, instrumentation_context)
        instrumentation_context[:result] = result
        result
      end
    end

    private

    def overrides
      Thread.current[:vexi_overrides] ||= {}
    end

    def instrument_evaluation_details(instrumentation_context, details)
      instrumentation_context[:result] = details.result
      instrumentation_context[:result_reason] = details.reason
      instrumentation_context[:responded_with_default_value] = true if details.default?
      instrumentation_context[:evaluation_unsuccessful] = true if details.error
    end

    def flatten_actors(actors)
      actors.flat_map { |element| element.is_a?(Array) ? element : [element] }
    end

    def enabled_internal(name, actors, default_value, instrumentation_context)
      begin
        _, override_value = overrides.find { |key, value| File.fnmatch?(key, name.to_s) }
        if !override_value.nil?
          return EvaluationDetails.new(result: override_value, reason: ResultReason::OVERRIDE)
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
        return EvaluationDetails.new(result: default_value, reason: ResultReason::ERROR, error: e)
      end

      if feature_flag.nil? || feature_flag.not_found
        return EvaluationDetails.new(result: default_value, reason: ResultReason::NOT_FOUND)
      end

      if feature_flag.boolean_gate_enabled?
        return EvaluationDetails.new(result: true, reason: ResultReason::FULLY_ENABLED)
      end
      if feature_flag.percentage_of_calls_enabled?
        return EvaluationDetails.new(result: true, reason: ResultReason::PERCENTAGE_OF_CALLS)
      end

      actor_ids = []
      nil_actor_indices = []
      invalid_actor_type_indices = []
      only_flipper_actor_indices = []

      actors.each_with_index do |actor, index|
        if actor.nil?
          nil_actor_indices << index
          next
        end

        if !actor.is_a?(String) && !actor.respond_to?(:vexi_id) && actor.respond_to?(:flipper_id)
          actor_ids <<         (actor).flipper_id
          only_flipper_actor_indices << index
          next
        end

        actor_id = Actor.get_actor_id(actor)
        if actor_id.nil?
          invalid_actor_type_indices << index
          next
        end
        actor_ids << actor_id
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

      if feature_flag.percentage_of_actors_enabled?(actor_ids)
        return EvaluationDetails.new(result: true, reason: ResultReason::PERCENTAGE_OF_ACTORS)
      end

      if feature_flag.any_actor_enabled?(actor_ids)
        return EvaluationDetails.new(result: true, reason: ResultReason::ACTOR_MATCH_EMBEDDED)
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
        # In the event of a segment error, don't immediately return. We need to still evaluate any custom gates.
        segment_error = e
      end

      return EvaluationDetails.new(result: true, reason: ResultReason::ACTOR_MATCH_SEGMENT) if segments.any? do |segment|
        segment.any_actor_enabled?(actor_ids)
      end

      begin
        # If the custom gates evaluator is not set, we will silently ignore the custom gates even if they are present.
        if feature_flag.custom_gates.any? && @custom_gate_evaluator
          instrumentation_context.instrument_timing(:custom_gates) do |properties|
            result = @custom_gate_evaluator.enabled?(feature_flag.name, feature_flag.custom_gates, actors)
            properties[:result] = result
            if result
              return EvaluationDetails.new(result: true, reason: ResultReason::CUSTOM_GATE)
            end
          end
        end
      rescue StandardError => e
        instrumentation_context.instrument_error(:"custom_gate_evaluator.error", e, message: "error evaluating custom gates")
        custom_gate_error = e
      end

      if segment_error || custom_gate_error
        # In the event of both a custom gate and segment error, let the custom gate error take precedence.
        e = custom_gate_error || segment_error
        return EvaluationDetails.new(result: default_value, reason: ResultReason::ERROR, error: e)
      end

      EvaluationDetails.new(result: false, reason: ResultReason::ALL_CHECKS_FALSE)
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

    # This method fetches a feature flag by name and handles various error conditions.
    # Unlike some other methods in this class, this method will raise an exception
    # if the feature flag is not found, as there's no meaningful default value to return
    # for flag details.
    #
    # @param name [String] The name of the feature flag to retrieve
    # @param instrumentation_context [Hash] Context for tracking evaluation metrics and errors
    #
    # @return [FeatureFlag] The feature flag object containing flag details
    #
    # @raise [StandardError] Re-raises any errors from the underlying feature flag service
    # @raise [Errors::ValidationError] Raised when the feature flag is not found or nil
    #
    # @note This method will always raise an exception for missing flags since there's
    #   no sensible default value to return for flag details, unlike boolean evaluation
    #   methods that can return false as a safe default.
    def get_flag_details_or_raise(name, instrumentation_context)
      begin
        feature_flag = @feature_flag_service.get(
          name,
          fetch_directly_from_adapter: false,
          cache_without_expiry: false,
          raise_on_cache_breaker_open: true,
          instrumentation_context: instrumentation_context,
        )
      rescue StandardError => e
        instrumentation_context[:evaluation_unsuccessful] = true
        instrumentation_context[:result_reason] = ResultReason::ERROR
        instrumentation_context.instrument_error(:"feature_flag.adapter.error", e, message: "error getting feature flag")
        raise e
      end

      feature_flag
    end

    def default_segment_name(feature_name)
      Vexi::DEFAULT_SEGMENT_PREFIX + feature_name.to_s
    end
  end
end
