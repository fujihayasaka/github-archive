# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    class BusinessModelRegistryFormComponent < ApplicationComponent
      renders_one :description
      renders_one :note

      sig do params(model: Copilot::ModelsRegistryCache, configurable: ::Business, disabled: T::Boolean).void
      end
      def initialize(model:, configurable:, disabled: false)
        @model = model
        @copilot_business = T.let(Copilot::Business.new(configurable), (Copilot::Business))
        @current_value = T.let(@copilot_business.model_policy(@model.model_key), String)
        @configurable = configurable
        @disabled = disabled
      end

      sig { returns(T::Boolean) }
      def render?
        logged_in?
      end

      private

      sig { returns(T::Boolean) }
      def accessible?
        return true if @copilot_business.can_access_copilot_enterprise_models?
        @model.plans.include?("business")
      end

      sig { returns(T::Array[Copilot::Policies::MenuItems::GeneralPolicies::Base]) }
      def menu_items
        items = Copilot::Policies::Menus::DEFAULT.map do |item|
          item_instance = item.new(copilot_configurable: @copilot_business, checked: @current_value == item.value)
          if item_instance.render?
            item_instance
          else
            nil
          end
        end

        items.compact
      end

      sig { returns(String) }
      def submit_path
        update_settings_copilot_policy_enterprise_path(@configurable)
      end

      sig { returns(String) }
      def current_label
        if accessible?
          menu_items.find { |item| item.checked }&.label || "Unconfigured"
        else
          "Not Accessible for Copilot Plan"
        end
      end
    end
  end
end
