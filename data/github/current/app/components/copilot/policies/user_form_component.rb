# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    class UserFormComponent < ApplicationComponent
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

      sig do params(
        policy_class: Copilot::Policy,
        enablement_text: String,
        setting_changed: T::Boolean,
        policy_blocked_by: String,
        copilot_user: Copilot::User,
        menu_items: T::Array[T.class_of(Copilot::Policies::MenuItems::GeneralPolicies::Base)],
      ).void
      end
      def initialize(
        policy_class:,
        enablement_text:,
        setting_changed:,
        policy_blocked_by:,
        copilot_user:,
        menu_items: Copilot::Policies::Menus::DEFAULT)

        @value = T.let(policy_class.value(copilot_user), String)
        @policy_name = T.let(policy_class.config_name, String)
        @display_name = T.let(policy_class.display_name, String)
        @enablement_text = enablement_text
        @setting_changed = setting_changed
        @menu_items = menu_items
        @copilot_user = copilot_user
        @policy_blocked_by = policy_blocked_by
        @preview = T.let(policy_class.preview?(copilot_user), T::Boolean)
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
