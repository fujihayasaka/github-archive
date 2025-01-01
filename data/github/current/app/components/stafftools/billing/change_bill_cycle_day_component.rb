# typed: strict
# frozen_string_literal: true

module Stafftools
  module Billing
    class ChangeBillCycleDayComponent < ApplicationComponent
      include StafftoolsHelper
      include Stafftools::BillingHelper

      sig do
        params(
          user: T.nilable(T.any(::User, ::Organization)),
          purpose: Symbol,
        ).void
      end
      def initialize(user:, purpose: Customer::DEFAULT_PURPOSE)
        @user = user
        @purpose = purpose
      end

      sig { returns(T.nilable(T.any(::User, ::Organization))) }
      attr_reader :user

      sig { returns Symbol }
      attr_reader :purpose

      sig { returns T::Boolean  }
      def render?
        return false unless user.present?
        return false if required_user.business.present?

        return show_change_bill_cycle_day? if purpose == Customer::DEFAULT_PURPOSE
        return show_change_sponsors_bill_cycle_day? if purpose == :sponsors
        false
      end

      sig { returns(T::Boolean) }
      def show_change_bill_cycle_day?
        return false if required_user.customer&.billed_via_billing_platform?

        !required_user.invoiced? || required_user.customer.present?
      end

      sig { returns(T::Boolean) }
      def show_change_sponsors_bill_cycle_day?
        return false unless GitHub.sponsors_enabled?
        return false if required_user.sponsors_customer&.billed_via_billing_platform?
        !required_user.sponsors_invoiced? || required_user.sponsors_customer.present?
      end

      sig { returns Integer }
      def bill_cycle_day
        if sponsors_purpose?
          required_user.sponsors_customer_bill_cycle_day
        else
          required_user.customer_bill_cycle_day
        end
      end

      sig { returns(T.any(::User, ::Organization)) }
      def required_user
        T.must(user)
      end

      sig { returns String }
      def dialog_id
        "change-#{purpose}-bill-cycle-day-dialog"
      end

      sig { returns T::Boolean }
      def sponsors_purpose?
        purpose == :sponsors
      end
    end
  end
end
