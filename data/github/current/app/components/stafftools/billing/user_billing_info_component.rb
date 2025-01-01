# typed: strict
# frozen_string_literal: true

module Stafftools
  module Billing
    class UserBillingInfoComponent < ApplicationComponent
      include StafftoolsHelper
      include Stafftools::BillingHelper

      # user - a User or Organization
      # show_billing_audit_log_link - Boolean indicating whether a link to the billing audit log for the given
      #                               user/organization should be shown
      # available_plan_options - an Array of Arrays for use with Rails' #options_for_select for showing a select
      #                          menu of options for changing the given user/organization's plan
      sig do
        params(
          user: T.nilable(T.any(::User, ::Organization)),
          show_billing_audit_log_link: T::Boolean,
          available_plan_options: T::Array[T::Array[String]],
        ).void
      end
      def initialize(user:, show_billing_audit_log_link: false, available_plan_options: [])
        @user = T.let(user, T.nilable(T.any(::User, ::Organization)))
        @show_billing_audit_log_link = T.let(show_billing_audit_log_link, T::Boolean)
        @available_plan_options = T.let(available_plan_options, T::Array[T::Array[String]])
      end

      sig { returns(T::Boolean) }
      def render?
        user.present?
      end

      private

      sig { returns(T.nilable(T.any(::User, ::Organization))) }
      attr_reader :user

      sig { returns(T::Array[T::Array[String]]) }
      attr_reader :available_plan_options

      delegate :scheduled_ofac_downgrade, :zuora_account?, :customer, :plan_subscriptions, :zuora_subscription?,
        to: :user

      sig { returns(T.nilable(Customer)) }
      memoize def sponsors_only_customer
        if GitHub.sponsors_enabled?
          cust = required_user.sponsors_customer
          cust if cust&.zuora?
        end
      end

      sig { returns(T.nilable(Integer)) }
      memoize def sponsors_bill_cycle_day
        if GitHub.sponsors_enabled?
          required_user.sponsors_customer_bill_cycle_day
        end
      end

      sig { returns(T::Boolean) }
      def show_billing_audit_log_link?
        @show_billing_audit_log_link
      end

      sig { returns(T::Boolean) }
      def in_business?
        required_user.business.present?
      end

      sig { returns(T::Boolean) }
      memoize def can_manual_charge?
        if !required_user.can_be_manually_charged?
          # Cannot bill someone with no card on file
          false
        elsif required_user.payment_amount.zero?
          # We can't charge someone who doesn't owe anything
          false
        elsif required_user.billed_on.nil?
          # If they've never paid us billed_on will be nil
          true
        elsif required_user.billed_on <= Date.today
          # If the billed_on is in the past, they're fair game
          true
        elsif required_user.billing_attempts > 0
          # If they're having card issues, we may need to push a charge through
          true
        else
          # Otherwise, nooooope
          false
        end
      end

      sig { returns(String) }
      def manual_charge_explanation
        if can_manual_charge?
          "Force the payment method on file to be charged."
        elsif required_user.payment_amount.zero?
          "No payment due, active coupon covers the current plan."
        elsif required_user.has_valid_payment_method?
          "The #{required_user.friendly_payment_method_name} on file cannot be manually charged until #{required_user.billed_on}."
        else
          "There is no payment method on file to charge."
        end
      end

      sig { returns(ActiveSupport::TimeWithZone) }
      memoize def metered_quota_resets_at
        required_user.next_metered_billing_cycle_starts_at
      end

      sig { returns(Date) }
      def calculated_metered_quota_reset_date
        required_user.advanced_metered_cycle_reset_date || (::GitHub::Billing.today + 1.month).beginning_of_month
      end

      sig { returns(T::Boolean) }
      def for_organization?
        required_user.organization?
      end

      sig { returns(T.nilable(Integer)) }
      memoize def total_billing_managers
        organization!.billing_managers.count
      end

      sig { returns(T.nilable(Date)) }
      def current_term_end_date
        required_user.billed_on - 1.day if required_user.billed_on
      end

      sig { returns(Integer) }
      memoize def customer_bill_cycle_day
        required_user.customer_bill_cycle_day
      end

      sig { returns(T.any(::User, ::Organization)) }
      def required_user
        T.must(user)
      end

      sig { returns(::Organization) }
      def organization!
        T.cast(required_user, ::Organization)
      end

      sig { returns(T::Boolean) }
      def show_patreon_status?
        sponsors_patreon_user.present? && patreon_link.present?
      end

      sig { returns(T.nilable(String)) }
      memoize def patreon_link
        sponsors_patreon_user&.patreon_link
      end

      sig { returns(T.nilable(SponsorsPatreonUser)) }
      def sponsors_patreon_user
        required_user.sponsors_patreon_user
      end
    end
  end
end
