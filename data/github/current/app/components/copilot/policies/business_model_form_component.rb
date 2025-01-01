# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    class BusinessModelFormComponent < ApplicationComponent
      renders_one :description
      renders_one :note

      sig do params(
        policy_class: Copilot::Policy,
        configurable: (::Business),
        disabled: T::Boolean,
        not_accessible: T::Boolean
        ).void
      end
      def initialize(
          policy_class:,
          configurable:,
          disabled: false,
          not_accessible: false
        )
        @policy_class = policy_class
        @display_name = T.let(policy_class.display_name, String)
        @configurable = configurable
        @copilot_business = T.let(copilot_object(configurable), (Copilot::Business))
        @policy_name = T.let(policy_class.config_name, String)
        @current_value = T.let(policy_class.value(@copilot_business), String)
        @preview = T.let(policy_class.preview?(@copilot_business), T::Boolean)
        @disabled = disabled
        @not_accessible = not_accessible
      end

      sig { returns(T::Boolean) }
      def render?
        logged_in?
      end

      private

      sig { returns(String) }
      def ui_title
        "#{@display_name} in Copilot"
      end

      sig { returns(T::Array[Copilot::Policies::MenuItems::GeneralPolicies::Base]) }
      def menu_items
        Copilot::Policies::Menus::DEFAULT.map do |item|
          item_instance = item.new(copilot_configurable: @copilot_business, checked: @current_value == item.value)
          if item_instance.render?
            item_instance
          else
            nil
          end
        end.compact
      end

      sig { returns(String) }
      def submit_path
        update_settings_copilot_policy_enterprise_path(@configurable)
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
          menu_items.find { |item| item.checked }&.label || "Unconfigured"
        end
      end
    end
  end
end
