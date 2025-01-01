# typed: strict
# frozen_string_literal: true

module Copilot
  module Purchase
    class IneligibleInfoComponent < ApplicationComponent
      include GitHub::Memoizer
      include Copilot::Purchase::Helpers

      sig { returns(T.any(::Organization, ::Business)) }
      attr_reader :selected_account

      sig { returns(Copilot::Purchase::Eligibility) }
      attr_reader :eligibility

      sig { returns(Copilot::Purchase::Eligibility::EligibilityReason) }
      attr_reader :eligibility_status

      sig { params(selected_account: T.any(::Organization, ::Business), eligibility: Copilot::Purchase::Eligibility).void }
      def initialize(selected_account:, eligibility:)
        @selected_account = selected_account
        @eligibility = eligibility
        @eligibility_status = T.let(eligibility.for(selected_account), Copilot::Purchase::Eligibility::EligibilityReason)
      end

      sig { override.void }
      def before_render
        @user = T.let(current_user, T.nilable(::User))
      end

      sig { returns(T::Boolean) }
      def render?
        !@eligibility_status[:eligible] && (
          @eligibility_status[:reason] == :copilot_enabled ||
          @eligibility_status[:reason] == :has_trial ||
          @eligibility_status[:reason] == :copilot_disabled_by_parent ||
          @eligibility_status[:reason] == :has_legacy_plan ||
          @eligibility_status[:reason] == :not_billable ||
          @eligibility_status[:reason] == :owned_by_parent
        )
      end

      sig { returns(T::Boolean) }
      memoize def account_is_adminable_by_user?
        return false unless @user.present?

        if has_parent_enterprise?
          return T.must(T.cast(@selected_account, ::Organization).business).adminable_by?(@user)
        end

        true
      end

      private

      sig { returns(T.nilable(Symbol)) }
      memoize def reason
        @eligibility_status[:reason]
      end

      sig { returns(String) }
      memoize def settings_path
        if selected_account.is_a?(::Organization)
          settings_org_copilot_seat_management_path(selected_account)
        else
          settings_copilot_enterprise_path(selected_account)
        end
      end

      sig { returns(String) }
      memoize def normalized_account_type
        is_organization? ? "organization" : "enterprise"
      end

      sig { returns(T::Boolean) }
      memoize def is_standalone_business?
        return false unless is_business?

        Copilot::Business.new(T.cast(selected_account, ::Business)).is_standalone_business?
      end

      sig { returns(T::Boolean) }
      memoize def is_business?
        account_type(selected_account).downcase == "enterprise"
      end

      sig { returns(T::Boolean) }
      memoize def is_organization?
        account_type(selected_account).downcase == "organization"
      end

      sig { returns(T::Boolean) }
      memoize def has_parent_enterprise?
        @selected_account.is_a?(::Organization) && @selected_account.business.present?
      end
    end
  end
end
