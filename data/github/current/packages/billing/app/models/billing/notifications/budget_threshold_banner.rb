# typed: true
# frozen_string_literal: true

module Billing
  module Notifications
    class BudgetThresholdBanner
      include UrlHelpers

      delegate :text, :variant, to: :serialized_budget_notification
      attr_reader :budget_notification

      sig { params(budget_notification: Billing::Notifications::BudgetNotification, actor: User).void }
      def initialize(budget_notification:, actor:)
        @budget_notification = budget_notification
        @serialized_budget_notification = budget_notification.serialize
        @actor = actor
      end

      sig { returns(T::Boolean) }
      def visible?
        !dismissed_by_actor?
      end

      sig { returns(T::Boolean) }
      def dismissible?
        true
      end

      sig { returns(String) }
      def dismissal_path
        billing_notifications_dismissals_path \
          account_id: billable_owner.id,
          account_type: billable_owner.class.name,
          notice_key: notification_key,
          product_tags: [budget_notification.budget.product_name]
      end

      def budget_uuid
        budget_notification.budget.uuid
      end

      sig { returns(String) }
      def notification_key
        slug = budget_notification.budget.slug
        threshold = serialized_budget_notification.threshold

        "billing_platform-budget_#{slug}-threshold_#{threshold}"
      end

      sig { returns(T.any(Business, Organization, User)) }
      def billable_owner
        @billable_owner ||= budget_notification.billable_owner
      end

      private

      attr_reader :serialized_budget_notification, :actor

      sig { returns(T::Boolean) }
      def dismissed_by_actor?
        notice_dismissal.exists?(notification_key, product_tag: budget_notification.budget.product_name)
      end

      sig { returns(Billing::Notifications::Dismissal) }
      def notice_dismissal
        @notice_dismissal ||= Billing::Notifications::Dismissal.new \
          account: billable_owner,
          actor_id: actor.id
      end
    end
  end
end
