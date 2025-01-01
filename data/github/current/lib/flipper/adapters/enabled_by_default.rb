# typed: true
# frozen_string_literal: true

module Flipper
  module Adapters
    # Adapter decorator that makes features default to enabled if not otherwise
    # specified.
    class EnabledByDefault
      include ::Flipper::Adapter

      def self.reset
        Flipper::Config.mysql_adapter.try(:reset_accessed_features)
      end

      attr_reader :name

      def initialize(adapter)
        @adapter = adapter
        @name = :enabled_by_default
        @exclusions = Set.new
        @accessed = Set.new
      end

      # Public: Prevent a feature from being enabled by default by adding it to
      # the exclusions list.
      #
      # feature_name - The String or Symbol name of the feature to exclusions list
      #
      # Returns nothing.
      def exclude(feature_name)
        @exclusions << feature_name.to_s
      end

      # Internal: Standard Adapter#get method, with features enabled by
      # default.
      def get(feature)
        state = @adapter.get(feature)

        # Default boolean state to true if no other gates are set
        feature_key = feature.key.to_s
        if !@accessed.include?(feature_key) && !@exclusions.include?(feature_key)
          state[:boolean] = "true"
        end

        state
      end

      # Public: The set of known features.
      def features
        @adapter.features
      end

      # Public: Adds a feature to the set of known features.
      def add(feature)
        added = @adapter.add(feature)
        @accessed.add(feature.key.to_s) if added
        added
      end

      # Public: Removes a feature from the set of known features and clears
      # all the values for the feature.
      def remove(feature)
        removed = @adapter.remove(feature)
        @accessed.delete(feature.key.to_s) if removed
        removed
      end

      # Public: Clears all the gate values for a feature.
      def clear(feature)
        @adapter.clear(feature)
      end

      # Public
      def enable(feature, gate, thing)
        enabled = @adapter.enable(feature, gate, thing)
        @accessed.add(feature.key.to_s) if enabled
        enabled
      end

      # Public
      def disable(feature, gate, thing)
        disabled = @adapter.disable(feature, gate, thing)
        @accessed.add(feature.key.to_s) if disabled
        disabled
      end

      # Public
      def feature_enabled?(feature_key, actor_id)
        @adapter.feature_enabled?(feature_key, actor_id)
      end

      # Public
      def actors_value(feature_key)
        @adapter.actors_value(feature_key)
      end

      # Public
      def reset_accessed_features
        @accessed.replace(features)
      end
    end
  end
end
