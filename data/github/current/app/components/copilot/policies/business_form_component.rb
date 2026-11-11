# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    class BusinessFormComponent < ApplicationComponent
      renders_one :description
      renders_one :note

      sig do params(
        policy_class: Copilot::PolicyInterface,
        configurable: (::Business),
        tab: String,
        menu_items: T::Array[T.class_of(Copilot::Policies::MenuItems::GeneralPolicies::Base)],
        display_name: T.nilable(String),
        disabled: T::Boolean,
        not_accessible: T::Boolean,
        can_write: T::Boolean,
        return_to: T.nilable(String),
        current_value: T.nilable(String)
        ).void
      end
      def initialize(
          policy_class:,
          configurable:,
          tab: "policies",
          menu_items: Copilot::Policies::Menus::DEFAULT,
          display_name: nil,
          disabled: false,
          not_accessible: false,
          can_write: true,
          return_to: nil,
          current_value: nil
        )
        @policy_class = policy_class
        resolved_display_name = display_name.present? ? display_name : policy_class.display_name
        @display_name = T.let(resolved_display_name, String)
        @configurable = configurable
        @copilot_business = T.let(copilot_object(configurable), (Copilot::Business))
        @policy_name = T.let(policy_class.config_name, String)
        @current_value = T.let(current_value || policy_class.value(@copilot_business), String)
        @preview = T.let(policy_class.preview?(@copilot_business), T::Boolean)
        @dpa_covered = T.let(policy_class.dpa_covered?, T::Boolean)
        @tab = tab
        @menu_items = menu_items
        @disabled = disabled
        @not_accessible = not_accessible
        @can_write = T.let(can_write, T::Boolean)
        @return_to = return_to
      end

      sig { returns(T::Boolean) }
      def render?
        logged_in?
      end

      private

      sig { returns(T::Array[Copilot::Policies::MenuItems::GeneralPolicies::Base]) }
      def menu_items
        @menu_items.map do |item|
          item_instance = item.new(copilot_configurable: @copilot_business, checked: @current_value == item.value)
          item_instance if item_instance.send(:render?)
        end.compact
      end

      sig { returns(String) }
      def submit_path
        if FeatureFlag.vexi.enabled?(:enterprise_ai_controls, @configurable, default: false) && @return_to.present?
          update_settings_copilot_policy_enterprise_path(@configurable, return_to: @return_to)
        else
          update_settings_copilot_policy_enterprise_path(@configurable)
        end
      end

      sig { params(configurable_object: (::Business)).returns(Copilot::Business) }
      def copilot_object(configurable_object)
        Copilot::Business.new(configurable_object)
      end

      sig { returns(Integer) }
      def description_mb
        note? ? 0 : 1
      end

      sig { returns(String) }
      def current_label
        if @not_accessible
          "Not Accessible for Copilot Plan"
        else
          menu_items.find { |item| item.checked? }&.label || "Unconfigured"
        end
      end
    end
  end
end
