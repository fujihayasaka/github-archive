# typed: true
# frozen_string_literal: true

module Flipper
  module Adapters
    # Adapter decorator that allows temporarily overriding whether a feature is
    # enabled or disabled.
    class Override
      include ::Flipper::Adapter

      def self.enables
        Thread.current[:flipper_override_enables] ||= []
      end

      def self.disables
        Thread.current[:flipper_override_disables] ||= []
      end

      def self.enables=(value)
        Thread.current[:flipper_override_enables] = value
      end

      def self.disables=(value)
        Thread.current[:flipper_override_disables] = value
      end

      attr_reader :name, :adapter

      def initialize(adapter)
        @adapter = adapter
        @name = :override
        reset_overrides
      end

      def adapter_enabled?
        return true if !@adapter.respond_to?(:adapter_enabled?)
        @adapter.adapter_enabled?
      end

      # Public: Override one or more features. Features matching the passed-in
      # pattern will be temporarily enabled or disabled until reset_overrides
      # is called.
      #
      # pattern - A fnmatch-style pattern to match feature names against.
      # enabled - A Boolean specifying whether the features should be enabled
      #           (true) or disabled (false).
      def override_features(pattern, enabled:)
        if enabled
          self.class.enables << pattern.to_s
        else
          self.class.disables << pattern.to_s
        end
      end

      # Public: Reset all overridden features.
      def reset_overrides
        self.class.enables = []
        self.class.disables = []
      end

      # Internal: Standard Adapter#get method, with support for overrides.
      def get(feature)
        if match?(self.class.enables, feature)
          { boolean: true }
        elsif match?(self.class.disables, feature)
          { boolean: false }
        else
          @adapter.get(feature)
        end
      end

      # Internal: Standard Adapter#get_multi method, with support for overrides.
      def get_multi(features)
        overrides = {}
        lookups = []

        features.each do |feature|
          if match?(self.class.enables, feature)
            overrides[feature] = { boolean: true }
          elsif match?(self.class.disables, feature)
            overrides[feature] = { boolean: false }
          else
            lookups << feature
          end
        end

        @adapter.get_multi(lookups).merge(overrides)
      end

      # Public: The set of known features.
      def features
        @adapter.features
      end

      # Public: Adds a feature to the set of known features.
      def add(feature)
        @adapter.add(feature)
      end

      # Public: Removes a feature from the set of known features and clears
      # all the values for the feature.
      def remove(feature)
        @adapter.remove(feature)
      end

      # Public: Clears all the gate values for a feature.
      def clear(feature)
        @adapter.clear(feature)
      end

      # Public
      def enable(feature, gate, thing)
        @adapter.enable(feature, gate, thing)
      end

      # Public
      def disable(feature, gate, thing)
        @adapter.disable(feature, gate, thing)
      end

      private

      def match?(overrides, feature)
        overrides.any? { |pattern| File.fnmatch?(pattern, feature.key) }
      end
    end
  end
end
