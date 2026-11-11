# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    class BusinessModelRegistryFormComponent < ApplicationComponent
      renders_one :description
      renders_one :note

      sig do params(model: Copilot::ModelsRegistryCache, copilot_business: Copilot::Business, disabled: T::Boolean, can_access_copilot_enterprise_models: T.nilable(T::Boolean)).void
      end
      def initialize(model:, copilot_business:, disabled: false, can_access_copilot_enterprise_models: nil)
        @model = model
        @copilot_business = copilot_business
        @current_value = T.let(@copilot_business.model_policy(@model.model_key), String)
        @configurable = copilot_business
        @disabled = disabled
        @can_access_copilot_enterprise_models = can_access_copilot_enterprise_models
        if can_access_copilot_enterprise_models.nil?
          # fallback to the evaluated value if nil
          GitHub.dogstats.increment("copilot.business_model_registry_form_component.evaluate_access_to_enterprise_models")
          @can_access_copilot_enterprise_models = @copilot_business.can_access_copilot_enterprise_models?
        end
      end

      sig { returns(T::Boolean) }
      def render?
        logged_in?
      end

      private

      sig { returns(T::Boolean) }
      def accessible?
        return true if @can_access_copilot_enterprise_models
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
        update_settings_copilot_policy_enterprise_path(@copilot_business.business_object)
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
