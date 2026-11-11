# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    class UserSettingsRowComponent < ApplicationComponent
      include GitHub::Memoizer
      renders_one :description

      sig { returns(String) }
      attr_reader :value

      sig { returns(String) }
      attr_reader :policy_name

      sig { returns(String) }
      attr_reader :display_name

      sig { returns(String) }
      attr_reader :enablement_text

      sig { returns(T::Boolean) }
      attr_reader :setting_changed

      sig { returns(String) }
      attr_reader :policy_blocked_by

      sig { returns(T::Boolean) }
      attr_reader :preview

      sig { returns(T::Boolean) }
      attr_reader :sub_setting

      sig do params(
        value: String,
        policy_name: String,
        display_name: String,
        enablement_text: String,
        setting_changed: T::Boolean,
        policy_blocked_by: String,
        copilot_user: Copilot::User,
        menu_items: T::Array[T.class_of(Copilot::Policies::MenuItems::GeneralPolicies::Base)],
        preview: T::Boolean,
        sub_setting: T::Boolean
      ).void
      end
      def initialize(
        value:,
        policy_name:,
        display_name:,
        enablement_text:,
        setting_changed:,
        policy_blocked_by:,
        copilot_user:,
        menu_items: Copilot::Policies::Menus::DEFAULT,
        preview: false,
        sub_setting: false)
        @value = value
        @policy_name = policy_name
        @display_name = display_name
        @enablement_text = enablement_text
        @setting_changed = setting_changed
        @menu_items = menu_items
        @copilot_user = copilot_user
        @policy_blocked_by = policy_blocked_by
        @preview = preview
        @sub_setting = sub_setting
      end

      sig { returns(T::Array[Copilot::Policies::MenuItems::GeneralPolicies::Base]) }
      def menu_items
        @menu_items.map do |item|
          item_instance = item.new(copilot_configurable: @copilot_user, checked: @value == item.value)
          if item_instance.render?
            item_instance
          else
            nil
          end
        end.compact
      end
    end
  end
end
