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

      sig { returns(T::Boolean) }
      attr_reader :setting_changed

      sig { returns(T::Boolean) }
      attr_reader :sub_setting

      sig { returns(T::Boolean) }
      attr_reader :preview

      sig do params(
        policy_class: Copilot::PolicyInterface,
        setting_changed: T::Boolean,
        copilot_user: Copilot::User,
        has_single_seat: T::Boolean,
        all_policies: T.nilable(Copilot::Users::Policies::CopilotAllPolicies),
        menu_items: T::Array[T.class_of(Copilot::Policies::MenuItems::GeneralPolicies::Base)],
        readonly: T::Boolean,
        sub_setting: T::Boolean,
      ).void
      end
      def initialize(
        policy_class:,
        setting_changed:,
        copilot_user:,
        has_single_seat:,
        all_policies: nil,
        menu_items: Copilot::Policies::Menus::DEFAULT,
        readonly: false,
        sub_setting: false
      )
        @policy_class = T.let(policy_class, Copilot::PolicyInterface)
        @policy_name = T.let(policy_class.config_name, String)
        @display_name = T.let(policy_class.display_name, String)
        @setting_changed = setting_changed
        @menu_items = menu_items
        @copilot_user = copilot_user
        @preview = T.let(policy_class.preview?(copilot_user), T::Boolean)
        @readonly = readonly
        @has_single_seat = has_single_seat
        @sub_setting = sub_setting
        @all_policies = all_policies
        @value = T.let(@policy_class.effective_value(@copilot_user), String)
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

      sig { returns(T::Boolean) }
      memoize def effectively_enabled?
        @policy_class.effective_value(@copilot_user) == @policy_class.config_values[:enabled]
      end

      # renders the setting value for non-cfi users viewing their settings
      sig { returns(T.nilable(String)) }
      memoize def enablement_text
        return nil unless @readonly

        effective_value = @policy_class.effective_value(@copilot_user, @all_policies)

        return effective_value.titleize if effectively_enabled?

        @policy_class.config_values[:disabled].titleize
      end

      sig { returns(T.nilable(String)) }
      def policy_blocked_by
        return nil if @has_single_seat || @copilot_user.has_cfi_access? || effectively_enabled?

        @all_policies ||= @copilot_user.all_policies

        breakdown = T.let(@copilot_user.policy_breakdown(@all_policies, @policy_class.config_name.to_sym), Copilot::Users::Policies::CopilotSeatBreakdown)
        # This can also happen when an org policy says blocked in the org policy management page
        # but because the org has not explicitly choosen disabled (it's defaulting), the breakdown
        # does not show the org as blocking the policy.
        if breakdown[:disabled].empty? && breakdown[:enabled].empty?
          return "Your organization(s) have not enabled use of this feature."
        end

        return "" unless breakdown[:disabled].any?

        the_policy = breakdown[:disabled].first
        text = "This feature is blocked by "
        text += if the_policy[:type] == :organization
          render(Primer::Beta::Link.new(href: "/#{the_policy[:name]}", classes: "Link--inTextBlock")) { the_policy[:name] }
        elsif the_policy[:type] == :business
          render(Primer::Beta::Link.new(href: "/enterprises/#{the_policy[:name]}", classes: "Link--inTextBlock")) { the_policy[:name] }
        end

        if breakdown[:disabled].size > 1
          text += " and other organizations you are a member of."
        end

        text.html_safe # rubocop:disable Rails/OutputSafety
      end

    end
  end
end
