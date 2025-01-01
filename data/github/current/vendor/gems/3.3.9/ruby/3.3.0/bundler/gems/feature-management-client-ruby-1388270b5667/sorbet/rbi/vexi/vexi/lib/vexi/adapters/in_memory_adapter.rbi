# frozen_string_literal: true
# typed: strict

module Vexi
  module Adapters
    # Public: In memory adapter for Vexi.
    class InMemoryAdapter
      extend T::Sig
      extend T::Helpers

      include Adapter

      sig { params(mode: Integer, exception_feature_flags: T::Array[String]).void }
      def initialize(mode, exception_feature_flags: []); end

      sig { override.params(names: T::Array[String]).returns(T::Array[GetFeatureFlagResponse]) }
      def get_feature_flags(names); end

      sig { override.params(_names: T::Array[String]).returns(T::Array[GetSegmentResponse]) }
      def get_segments(_names); end

      sig { override.returns String }
      def adapter_name; end

      # Below is the implementation of VexiManagement::Adapter to support using it with vexi_management,
      # but that is not included directly here to avoid adding gem dependencies.
      # For testing this can be used with vexi_management if desired, but alternatively
      # the methods can be used directly on the InMemoryAdapter class.

      # Creates a new feature flag with the given name. Will raise an error if the feature flag already exists.
      sig { params(feature_flag: FeatureFlag).void }
      def create(feature_flag); end

      sig { params(name: T.any(String, Symbol)).returns(T.nilable(FeatureFlag)) }
      def get(name); end

      # Deletes a feature flag from the adapter.
      sig { params(name: T.any(String, Symbol)).void }
      def delete(name); end

      # Fully enables the feature flag. It will create it if it does not exist.
      sig { params(name: T.any(String, Symbol)).void }
      def enable(name); end

      # Disables the feature flag. It will create it if it does not exist.
      sig { params(name: T.any(String, Symbol)).void }
      def disable(name); end

      # Adds an actor to the feature flag. Requires the feature flag to exist.
      sig { params(name: T.any(String, Symbol), actor: T.any(String, Actor)).void }
      def add_actor(name, actor); end

      # Removes an actor from the feature flag. Requires the feature flag to exist.
      sig { params(name: T.any(String, Symbol), actor: T.any(String, Actor)).void }
      def remove_actor(name, actor); end

      # Enables the feature flag for a percentage of calls. Requires the feature flag to exist.
      sig { params(name: T.any(String, Symbol), percentage: Float).void }
      def enable_percentage_of_calls(name, percentage); end

      # Enables the feature flag for a percentage of actors. Requires the feature flag to exist.
      sig { params(name: T.any(String, Symbol), percentage: Float).void }
      def enable_percentage_of_actors(name, percentage); end

      # Adds a custom gate to the feature flag. Requires the feature flag to exist.
      sig { params(name: T.any(String, Symbol), custom_gate: String).void }
      def add_custom_gate(name, custom_gate); end

      # Removes a custom gate from the feature flag. Requires the feature flag to exist.
      sig { params(name: T.any(String, Symbol), custom_gate: String).void }
      def remove_custom_gate(name, custom_gate); end

      # Resets the adapter to its initial state.
      sig { void }
      def reset; end
    end
  end
end
