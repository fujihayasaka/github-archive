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
