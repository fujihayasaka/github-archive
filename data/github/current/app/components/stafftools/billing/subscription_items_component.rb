# typed: strict
# frozen_string_literal: true

module Stafftools
  module Billing
    class SubscriptionItemsComponent < ApplicationComponent
      sig { returns(T::Array[::Billing::SubscriptionItem]) }
      attr_reader :active_subscription_items
      sig { returns(T::Array[::Billing::SubscriptionItem]) }
      attr_reader :cancelled_subscription_items
      sig { returns(::Billing::Types::Account) }
      attr_reader :account
      sig { returns(::User) }
      attr_reader :current_user

      sig { params(account: ::Billing::Types::Account, active: T::Array[::Billing::SubscriptionItem], cancelled: T::Array[::Billing::SubscriptionItem], current_user: ::User).void }
      def initialize(account:, active:, cancelled:, current_user:)
        @account = account
        @active_subscription_items = active
        @cancelled_subscription_items = cancelled
        @current_user = current_user
      end

      sig { params(item: ::Billing::SubscriptionItem).returns(T::Boolean) }
      def can_cancel_and_refund_item?(item)
        return false unless item.active?
        return false unless item.paid?
        return false if item.in_app_purchase?

        true
      end

      sig { returns(T::Boolean) }
      def in_app_purchases?
        active_subscription_items.any?(&:in_app_purchase?)
      end

      sig { params(item: ::Billing::SubscriptionItem).returns(String) }
      def duration_for(item)
        case item.subscribable.billing_cycle
        when ::User::BillingDependency::MONTHLY_PLAN then "monthly"
        when ::User::BillingDependency::YEARLY_PLAN then "yearly"
        when ::Billing::ProductUUID::ONE_TIME_BILLING_CYCLE then "one-time"
        else item.subscribable.billing_cycle.to_s
        end
      end

      sig { params(item: ::Billing::SubscriptionItem).returns(T::Hash[Symbol, T.untyped]) }
      def active_state_label(item)
        if item.on_free_trial?
          { text: "Free trial", scheme: :accent, title: "Ends: #{item.free_trial_ends_on}" }
        elsif item.latest_billing_transaction&.success?
          { text: "Paid", scheme: :success, title: "Payment collected and recorded" }
        elsif item.apple_in_app_purchase?
          { text: "Managed by Apple", scheme: :success, title: "Payment & subscription managed via Apple App Store" }
        elsif item.google_in_app_purchase?
          { text: "Managed by Google", scheme: :success, title: "Payment & subscription managed via Google Play Store" }
        else
          { text: "Awaiting payment", scheme: :attention, title: "Payment not collected" }
        end
      end

      sig { params(item: ::Billing::SubscriptionItem).returns(T::Hash[Symbol, T.untyped]) }
      def cancelled_state_label(item)
        if item.on_free_trial?
          { text: "Free trial", scheme: :accent, title: "Cancelled during free trial" }
        elsif item.latest_billing_transaction&.refund.present?
          { text: "Refunded", scheme: :done, title: "Payment refunded" }
        elsif item.latest_billing_transaction&.success?
          { text: "Paid", scheme: :success, title: "Payment collected and recorded" }
        else
          { text: "Payment not recorded", scheme: :secondary, title: "Payment not collected" }
        end
      end

      sig { params(item: ::Billing::SubscriptionItem).returns(T.nilable(String)) }
      def cancelled_transaction_path(item)
        transaction = item.latest_billing_transaction
        return unless transaction
        return unless transaction.success? || transaction.refund.present?

        billing_history_path("transaction-#{transaction.transaction_id}")
      end

      sig { params(item: ::Billing::SubscriptionItem).returns(String) }
      def subscription_item_path(item)
        if @account.is_a?(Business)
          helpers.stafftools_subscription_item_path(@account, item)
        else
          helpers.stafftools_user_subscription_item_path(@account, item)
        end
      end

      sig { returns(String) }
      def billing_path
        if @account.is_a?(Business)
          helpers.stafftools_enterprise_billing_path(@account)
        else
          helpers.billing_stafftools_user_path(@account)
        end
      end

      sig { params(anchor: String).returns(String) }
      def billing_history_path(anchor)
        if @account.is_a?(Business)
          helpers.stafftools_enterprise_billing_payment_history_path(@account, anchor: anchor)
        else
          helpers.stafftools_user_billing_history_path(@account, anchor: anchor)
        end
      end
    end
  end
end
