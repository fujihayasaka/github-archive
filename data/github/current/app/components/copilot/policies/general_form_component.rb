# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    class GeneralFormComponent < ApplicationComponent
      renders_one :description
      renders_one :note

      sig do params(
        display_name: String,
        configurable: (::Business),
        policy_name: String,
        current_value: String,
        preview: T::Boolean,
        tab: String,
        policy_prefix: T.nilable(String),
        menu_items: T::Array[T.class_of(Copilot::Policies::MenuItems::GeneralPolicies::Base)],
        disabled: T::Boolean,
        not_accessible: T::Boolean
        ).void
      end
      def initialize(
          display_name:,
          configurable:,
          policy_name:,
          current_value:,
          preview:,
          tab: "policies",
          policy_prefix: "copilot_",
          menu_items: Copilot::Policies::Menus::DEFAULT,
          disabled: false,
          not_accessible: false
        )
        @display_name = display_name
        @configurable = configurable
        @copilot_business = T.let(copilot_object(configurable), (Copilot::Business))
        @policy_name = policy_name
        @current_value = current_value
        @preview = preview
        @tab = tab
        # quick fix for policies like cli and desktop
        # remove when all policies use the general component
        # and we prefix all policies with copilot_
        @policy_prefix = policy_prefix
        @menu_items = menu_items
        @disabled = disabled
        @not_accessible = not_accessible
      end

      sig { returns(T::Boolean) }
      def render?
        logged_in?
      end

      sig { returns(String) }
      def name
        "#{@policy_prefix}#{@policy_name}"
      end

      private

      sig { returns(T::Array[Copilot::Policies::MenuItems::GeneralPolicies::Base]) }
      def menu_items
        @menu_items.map do |item|
          item_instance = item.new(copilot_configurable: copilot_object(@configurable), checked: @current_value == item.value)
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
