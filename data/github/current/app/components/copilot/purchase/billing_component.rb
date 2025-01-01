# typed: strict
# frozen_string_literal: true

module Copilot
  module Purchase
    class BillingComponent < ApplicationComponent

      include Copilot::Purchase::Helpers

      sig { returns(T.any(::Organization, ::Business)) }
      attr_reader :selected_account

      sig { returns(Copilot::Purchase::Eligibility::EligibilityReason) }
      attr_reader :eligibility

      sig { params(selected_account: T.any(::Organization, ::Business), eligibility: Copilot::Purchase::Eligibility::EligibilityReason).void }
      def initialize(selected_account:, eligibility:)
        @selected_account = selected_account
        @eligibility = eligibility
      end

      sig { override.void }
      def before_render
        @user = T.let(current_user, T.nilable(::User))
      end

      sig { override.returns(T::Boolean) }
      def render?
        return false unless @user.present?
        return false if is_or_manages_trial_account?
        return false if skip_payment_confirmation?

        # Regardless of the billable status of this account, any of the following
        # reasons mean this account cannot enable Copilot on it's own; therefore,
        # we do not need to show any billing information.
        reason = eligibility[:reason]
        return false if reason == :has_trial ||
          reason == :manages_trial ||
          reason == :copilot_enabled ||
          reason == :has_legacy_plan ||
          reason == :force_sales_serve

        true
      end

      sig { returns(T::Boolean) }
      def is_or_manages_trial_account?
        if selected_account.is_a?(::Business)
          return true if eligibility[:reason] == :has_trial || eligibility[:reason] == :manages_trial
        end

        eligibility[:reason] == :has_trial
      end

      # This method feels odd, but we do the same check in the business_signup controller
      # The only difference in that here we DO want to show the billing component
      # if the business is explicitly metered via azure.
      sig { returns(T::Boolean) }
      def skip_payment_confirmation?
        return false unless selected_account.is_a?(::Business)

        account = T.cast(selected_account, ::Business)
        !!(eligibility[:reason] == :ok &&
          !account.eligible_for_self_serve_payment? &&
          !has_azure_account?
        )
      end

      sig { returns(T::Boolean) }
      def can_see_billing?
        account_is_adminable_by_user? && !has_parent_enterprise?
      end

      sig { returns(T::Boolean) }
      def account_is_adminable_by_user?
        return false unless @user.present?

        if has_parent_enterprise?
          return T.must(T.cast(@selected_account, ::Organization).business).adminable_by?(@user)
        end

        true
      end

      sig { returns(T::Boolean) }
      def has_parent_enterprise?
        @selected_account.is_a?(::Organization) && @selected_account.business.present?
      end

      sig { returns(T::Boolean) }
      def has_azure_account?
        selected_account.customer&.azure_subscription_id.present?
      end

      sig { returns(T::Boolean) }
      def invoiced?
        selected_account.invoiced? && !has_azure_account?
      end

      sig  { returns(String) }
      def edit_billing_path
        if selected_account.is_a?(::Organization)
          settings_org_billing_path(selected_account)
        else
          settings_billing_enterprise_path(selected_account)
        end
      end
    end
  end
end
