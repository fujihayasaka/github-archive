# typed: true
# frozen_string_literal: true

module Billing
  module Settings
    class ManualPaymentAccountOverviewHeaderComponent < ApplicationComponent
      attr_reader :payment_due_date,
        :account_balance,
        :account_has_trade_restrictions,
        :bill_pay_href,
        :manage_spending_limit_href,
        :payment_information_href,
        :payment_history_href,
        :payment_method_needs_update,
        :update_payment_method_href,
        :redeem_coupon_href

      renders_one :switch_plan_duration_link_tag

      def initialize(
        account_balance_in_cents:,
        account_has_trade_restrictions:,
        bill_pay_href:,
        payment_due_date:,
        manage_spending_limit_href:,
        payment_information_href:,
        payment_history_href:,
        payment_method_needs_update: false,
        update_payment_method_href:,
        redeem_coupon_href:
      )
        @account_balance = ::Billing::Money.new(account_balance_in_cents)
        @account_has_trade_restrictions = account_has_trade_restrictions
        @bill_pay_href = bill_pay_href
        if payment_due_date.present?
          @payment_due_date = payment_due_date.respond_to?(:strftime) ? payment_due_date : Date.parse(payment_due_date)
        end
        @manage_spending_limit_href = manage_spending_limit_href
        @payment_information_href = payment_information_href
        @payment_history_href = payment_history_href
        @payment_method_needs_update = payment_method_needs_update
        @update_payment_method_href = update_payment_method_href
        @redeem_coupon_href = redeem_coupon_href
      end

      def pay_now_button_classes
        class_string = ""
        class_string += "disabled" if pay_now_disabled?

        class_string
      end

      def pay_now_disabled?
        !account_balance.positive?
      end

      def pay_now_button_href
        bill_pay_href
      end

      def formatted_payment_due_date
        if payment_due_date.nil?
          "--"
        elsif payment_due_date.past?
          "Overdue"
        else
          payment_due_date.strftime("%b %-d, %Y")
        end
      end

      def account_has_trade_restrictions?
        !!account_has_trade_restrictions
      end

      def payment_method_needs_update?
        payment_method_needs_update
      end

      def update_payment_method_link_class
        class_string = "f6"
        class_string += "color-fg-danger" if payment_method_needs_update?

        class_string
      end
    end
  end
end
