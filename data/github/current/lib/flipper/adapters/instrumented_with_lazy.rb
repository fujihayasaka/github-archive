# typed: true
# frozen_string_literal: true

require "flipper/adapters/instrumented"

module Flipper
  module Adapters
    # InstrumentedWithLazy reimplements Instrumented's methods
    # so that the conform to the interface that LazyActor needs.
    class InstrumentedWithLazy < ::Flipper::Adapters::Instrumented
      def feature_enabled?(feature_key, actor_id)
        payload = {
          operation: :feature_enabled,
          adapter_name: @adapter.name,
          feature_name: feature_key,
        }

        @instrumenter.instrument(InstrumentationName, payload) do |payload|
          payload[:result] = @adapter.feature_enabled?(feature_key, actor_id)
        end
      end

      def actors_value(feature_key)
        payload = {
          operation: :actors_value,
          adapter_name: @adapter.name,
          feature_name: feature_key,
        }

        @instrumenter.instrument(InstrumentationName, payload) do |payload|
          payload[:result] = @adapter.actors_value(feature_key)
        end
      end
    end
  end
end
