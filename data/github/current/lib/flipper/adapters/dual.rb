# typed: true
# frozen_string_literal: true

require "flipper"
require "flipper/adapters"

module Flipper
  module Adapters
    class Dual
      include ::Flipper::Adapter

      TTL = 15

      attr_accessor :new_adapter, :fallback_adapter

      def initialize(new_adapter, fallback_adapter, testing: false)
        @new_adapter = new_adapter
        @fallback_adapter = fallback_adapter
        @testing = testing
      end

      def reset_overrides
        @new_adapter.reset_overrides
        @fallback_adapter.reset_overrides
      end

      def features
        enabled_adapter.features
      end

      def get(feature)
        enabled_adapter.get(feature)
      end

      def get_multi(features)
        enabled_adapter.get_multi(features)
      end

      def get_all
        enabled_adapter.get_all
      end

      def feature_enabled?(feature_key, actor_id)
        enabled_adapter.feature_enabled?(feature_key, actor_id)
      end

      def actors_value(feature_key)
        enabled_adapter.actors_value(feature_key)
      end

      def add(feature)
        enabled_adapter.add(feature)
      end

      def remove(feature)
        enabled_adapter.remove(feature)
      end

      def clear(feature)
        enabled_adapter.clear(feature)
      end

      def enable(feature, gate, thing)
        enabled_adapter.enable(feature, gate, thing)
      end

      def disable(feature, gate, thing)
        enabled_adapter.disable(feature, gate, thing)
      end

      def reset_adapter_cache
        @timestamp = nil
        @enabled_adapter = nil
      end

      def enabled_adapter_type
        adapter = enabled_adapter
        adapter = adapter.adapter if adapter.is_a?(Flipper::Adapters::Override)
        adapter.class.to_s
      end

      private def enabled_adapter
        return @fallback_adapter if GitHub.enterprise?
        return @fallback_adapter if GitHub.component != :unicorn
        return @fallback_adapter if Rails.env.test? && !@testing

        if !defined?(@enabled_adapter) || @enabled_adapter.nil? || @timestamp < Time.now
          @timestamp = TTL.seconds.from_now
          @enabled_adapter = @new_adapter.adapter_enabled? ? @new_adapter : @fallback_adapter
        else
          @enabled_adapter
        end
      end
    end
  end
end
