# typed: true
# frozen_string_literal: true

module Billing
  module Notifications
    class CombinedBudgetThresholdBanner
      include UrlHelpers
      attr_reader :variant

      sig do
        params(
          budget_threshold_banners: T::Array[Billing::Notifications::BudgetThresholdBanner],
          variant: Symbol
        ).void
      end
      def initialize(budget_threshold_banners:, variant:)
        @budget_threshold_banners = budget_threshold_banners
        @variant = variant
      end

      sig { returns(T::Boolean) }
      def dismissible?
        true
      end

      sig { returns(String) }
      def text
        if variant == :critical
          hard_budget_text
        else
          soft_budget_text
        end
      end

      sig { returns(String) }
      def dismissal_path
        billing_notifications_combined_dismissals_path \
          account_id: account_id,
          account_type: account_type,
          dismissal_items: construct_dismissal_items
      end

      sig { returns(String) }
      def budget_uuid
        if budget_count == 1
          first_banner.budget_uuid
        else
          ""
        end
      end

      sig { returns(Billing::Notifications::BudgetThresholdBanner) }
      def first_banner
        budget_threshold_banners[0]
      end

      sig { returns T::Hash[Symbol, T.untyped] }
      def to_payload_hash
        {
          text: text,
          variant: variant.to_s,
          dismissible: dismissible?,
          dismiss_link: dismissal_path,
          budget_id: budget_uuid,
        }
      end

      private

      attr_reader :budget_threshold_banners

      sig { returns(Integer) }
      def budget_count
        budget_threshold_banners.length
      end

      sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
      def construct_dismissal_items
        budget_threshold_banners.map do |banner|
          {
            notice_key: banner.notification_key,
            product_tag: banner.budget_notification.budget.product_name
          }
        end
      end

      sig { returns(String) }
      def hard_budget_text
        if budget_count > 1
          text = "You've used 100% or more of #{budget_count} budgets in your account."
        else
          text = first_banner.text
        end
        text + " Additional usage will be stopped."
      end

      sig { returns(String) }
      def soft_budget_text
        if budget_count > 1
          "#{budget_count} budgets are approaching or have exceeded their limit in your account."
        else
          first_banner.text
        end
      end

      def account_id
        first_banner.billable_owner.id
      end

      def account_type
        first_banner.billable_owner.class.name
      end
    end
  end
end
