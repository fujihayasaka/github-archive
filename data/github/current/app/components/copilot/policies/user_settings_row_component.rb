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

      sig { returns(T::Array[T.any(Copilot::Policies::MenuItems::GeneralPolicies::Enabled, Copilot::Policies::MenuItems::GeneralPolicies::Disabled)]) }
      attr_reader :menu_items

      sig { returns(String) }
      attr_reader :policy_blocked_by

      sig { returns(T::Boolean) }
      attr_reader :preview

      sig do params(
        value: String,
        policy_name: String,
        display_name: String,
        enablement_text: String,
        setting_changed: T::Boolean,
        menu_items: T::Array[T.any(Copilot::Policies::MenuItems::GeneralPolicies::Enabled, Copilot::Policies::MenuItems::GeneralPolicies::Disabled)],
        policy_blocked_by: String,
        preview: T::Boolean,
      ).void
      end
      def initialize(
        value:,
        policy_name:,
        display_name:,
        enablement_text:,
        setting_changed:,
        menu_items:,
        policy_blocked_by:,
        preview: false)

        @value = value
        @policy_name = policy_name
        @display_name = display_name
        @enablement_text = enablement_text
        @setting_changed = setting_changed
        @menu_items = menu_items
        @policy_blocked_by = policy_blocked_by
        @preview = preview
      end
    end
  end
end
