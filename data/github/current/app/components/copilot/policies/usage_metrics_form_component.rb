# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    class UsageMetricsFormComponent < ApplicationComponent
      extend T::Sig
      include GitHub::Memoizer

      renders_one :form_content

      sig { params(configurable: T.any(::Organization, ::Business), button_type: String).void }
      def initialize(configurable:, button_type: "submit")
        @configurable = configurable
        @copilot_object = T.let(copilot_object(configurable), T.any(Copilot::Business, Copilot::Organization))
        @button_type = button_type
      end

      private

      sig { returns(T::Boolean) }
      memoize def standalone_business?
        return false unless @configurable.is_a?(::Business)
        @copilot_object.copilot_standalone?
      end

      sig { returns(T::Array[GitHub::Menu::ButtonComponent]) }
      memoize def menu_items
        items = if @configurable.is_a?(::Business)
          [
            Copilot::Policies::MenuItems::UsageTelemetryAggregation::NoPolicy,
            Copilot::Policies::MenuItems::UsageTelemetryAggregation::Enabled,
            Copilot::Policies::MenuItems::UsageTelemetryAggregation::Disabled
          ]
        else
          [
            Copilot::Policies::MenuItems::UsageTelemetryAggregation::Enabled,
            Copilot::Policies::MenuItems::UsageTelemetryAggregation::Disabled
          ]
        end

        items.map do |item|
          item.new(copilot_configurable: @copilot_object, type: @button_type).component
        end.compact
      end

      sig { returns(String) }
      memoize def submit_path
        update_settings_copilot_policy_enterprise_path(@configurable)
      end

      sig { params(configurable_object: T.any(::Organization, ::Business)).returns(T.any(Copilot::Business, Copilot::Organization)) }
      def copilot_object(configurable_object)
        if configurable_object.is_a?(::Business)
          Copilot::Business.new(configurable_object)
        else
          Copilot::Organization.new(configurable_object)
        end
      end
    end
  end
end
