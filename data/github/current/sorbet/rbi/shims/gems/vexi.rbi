# typed: strict
# frozen_string_literal: true

module Vexi
  # Public: The main Vexi class for performing feature flag enabled checks.
  class Client
    # Determine if a feature is enabled. Returns an evaluation details object containing result, reason, and error (if any).
    #
    # name
    #   The name of the feature flag.
    # actors (optional)
    #   One or more actors to check against the feature flag.
    #   If the feature flag is enabled for any of the provided actors, the method will return true.
    # default:
    #  The default value to return if the feature flag is not found or an error occurs while evaluating the feature flag state.
    sig do
      params(
        name: T.any(String, Symbol),
        actors: T.any(T.nilable(T.any(Actor, String)), T::Array[T.nilable(T.any(Actor, String))]),
        default: T::Boolean
      ).returns(EvaluationDetails)
    end
    def enabled_with_details(name, *actors, default:); end

    # Determine if a feature is enabled. Returns a boolean value.
    #
    # name
    #   The name of the feature flag.
    # actors (optional)
    #   One or more actors to check against the feature flag.
    #   If the feature flag is enabled for any of the provided actors, the method will return true.
    # default:
    #  The default value to return if the feature flag is not found or an error occurs while evaluating the feature flag state.
    sig do
      params(
        name: T.any(String, Symbol),
        actors: T.any(T.nilable(T.any(Actor, String)), T::Array[T.nilable(T.any(Actor, String))]),
        default: T::Boolean
      ).returns(T::Boolean)
    end
    def enabled?(name, *actors, default:); end

    # Determine if a feature is enabled. Returns a boolean value. Raises if an error occurs while evaluating feature flag state.
    #
    # name
    #   The name of the feature flag.
    # actors (optional)
    #   One or more actors to check against the feature flag.
    #   If the feature flag is enabled for any of the provided actors, the method will return true.
    sig do
      params(
        name: T.any(String, Symbol),
        actors: T.any(T.nilable(T.any(Actor, String)), T::Array[T.nilable(T.any(Actor, String))]),
      ).returns(T::Boolean)
    end
    def enabled_or_raise?(name, *actors); end

    # NOTE: This method is only there for compatibility with the old Flipper API.
    # It is not recommended to use this method in new code.
    #
    # Get a list of raw actors that are enabled for the feature flag.
    # Returns an empty array if the feature flag is not found.
    #
    # name
    #   The name of the feature flag.
    sig do
      params(
        name: T.any(String, Symbol)
      ).returns(T::Array[String])
    end
    def actors_value_or_raise(name); end

    # NOTE: This method is only there for compatibility with the old Flipper API.
    # It is not recommended to use this method in new code.
    #
    # Get the percentage of actors that the feature flag is enabled for.
    # Returns 0.0 if the feature flag is not found.
    #
    # name
    #   The name of the feature flag.
    sig do
      params(
        name: T.any(String, Symbol)
      ).returns(Float)
    end
    def percentage_of_actors_value_or_raise(name); end

    # NOTE: This method is only there for compatibility with the old Flipper API.
    # It is not recommended to use this method in new code.
    #
    # Get the percentage of calls that the feature flag is enabled for.
    # Returns 0.0 if the feature flag is not found.
    #
    # name
    #   The name of the feature flag.
    sig do
      params(
        name: T.any(String, Symbol)
      ).returns(Float)
    end
    def percentage_of_calls_value_or_raise(name); end

    # NOTE: This method is only there for compatibility with the old Flipper API.
    # It is not recommended to use this method in new code.
    #
    # Check if a feature flag is fully enabled (boolean gate is true or it was enabled for 100% of calls).
    # Returns false if the feature flag is not found.
    #
    # name
    #   The name of the feature flag.
    sig do
      params(
        name: T.any(String, Symbol)
      ).returns(T::Boolean)
    end
    def fully_enabled_or_raise?(name); end

    # NOTE: This method is only there for compatibility with the old Flipper API.
    # It is not recommended to use this method in new code.
    #
    # Check if a feature flag is fully disabled (no gates are active).
    # Returns true if the feature flag is not found.
    #
    # name
    #   The name of the feature flag.
    sig do
      params(
        name: T.any(String, Symbol)
      ).returns(T::Boolean)
    end
    def fully_disabled_or_raise?(name); end

    # NOTE: This method is only there for compatibility with the old Flipper API.
    # It is not recommended to use this method in new code.
    #
    # Check if a feature flag exists.
    # Returns false if the feature flag is not found.
    #
    # NOTE: Because of the way Vexi is implemented for tests, feature flags are created by default whenever they are loaded,
    # so unknown flags will always return true (exist) without raising an error. To work around this, you can stub the method in tests to get false:
    # `FeatureFlag.vexi.stubs(:exists_or_raise?).with(:feature_flag_name).returns(false)`
    #
    # name
    #   The name of the feature flag.
    sig do
      params(
        name: T.any(String, Symbol)
      ).returns(T::Boolean)
    end
    def exists_or_raise?(name); end

    # Enables or disables memoization.
    sig { params(value: T::Boolean).void }
    def memoize=(value); end

    # Returns true if memoization is currently enabled, false otherwise.
    sig { returns(T::Boolean) }
    def memoizing?; end

    # Clears the memoized values for a feature flag.
    sig { params(name: T.any(String, Symbol)).void }
    def clear_feature_flag_memoization(name); end

    # Override one or more features. Features matching the passed-in pattern will be temporarily enabled or disabled until clear_overrides is called.
    #
    # pattern - A fnmatch-style pattern to match feature names against.
    # enabled - A Boolean specifying whether the features should be enabled (true) or disabled (false).
    sig { params(pattern: T.any(String, Symbol), enabled: T::Boolean).void }
    def add_override(pattern, enabled:); end

    # Remove all feature overrides.
    sig { void }
    def clear_overrides; end

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
    sig do
      params(
        names: T::Array[T.any(String, Symbol)],
        fetch_directly_from_adapter: T::Boolean,
        cache_without_expiry: T::Boolean,
        instrumentation_properties: Instrumenter::NotificationContext
      ).returns(T::Boolean)
    end
    def preload(names, fetch_directly_from_adapter: false, cache_without_expiry: false, instrumentation_properties: {}); end

    # Preload the named feature flags and any related segments into the cache and/or memoization layer.
    # This version of the preload method will raise an error if an error occurs while preloading.
    sig do
      params(
        names: T::Array[T.any(String, Symbol)],
        fetch_directly_from_adapter: T::Boolean,
        cache_without_expiry: T::Boolean,
        instrumentation_properties: Instrumenter::NotificationContext
      ).returns(T::Boolean)
    end
    def preload_or_raise(names, fetch_directly_from_adapter: false, cache_without_expiry: false, instrumentation_properties: {}); end
  end

  class EvaluationDetails
    sig { returns(T::Boolean) }
    attr_reader :result

    sig { returns(String) }
    attr_reader :reason

    sig { returns(T.nilable(StandardError)) }
    attr_reader :error

    # Returns a boolean indicating if the default value was used for the result.
    sig { returns(T::Boolean) }
    def default?; end
  end
end
