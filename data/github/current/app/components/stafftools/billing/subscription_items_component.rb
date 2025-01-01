# typed: true
# frozen_string_literal: true

module Stafftools
  module Billing
    class SubscriptionItemsComponent < ApplicationComponent
      attr_reader :active_subscription_items, :cancelled_subscription_items, :user, :current_user

      def initialize(user:, active:, cancelled:, current_user:)
        @user = user
        @active_subscription_items = active
        @cancelled_subscription_items = cancelled
        @current_user = current_user
      end

      def can_cancel_and_refund_item?(item)
        return false unless item.active?
        return false unless item.paid?
        return false if item.in_app_purchase?

        true
      end

      def in_app_purchases?
        active_subscription_items.any?(&:in_app_purchase?)
      end
    end
  end
end
