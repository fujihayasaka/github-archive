# typed: true
# frozen_string_literal: true

module Billing
  module Notifications
    class BudgetNotificationSerializer < BaseThresholdNotificationSerializer
      delegate :budget, to: :notification

      sig { override.returns(T.untyped) }
      def resource
        budget
      end

      sig { override.returns(String) }
      def resource_type
        "budget"
      end

      sig { override.returns(String) }
      def mail_subject
        "You've hit #{result.threshold}% of your budget"
      end

      sig { override.returns(String) }
      def mail_product_title
        "Budget usage"
      end

      sig { override.returns(String) }
      def progress_bar_title
        "Budget"
      end

      sig { override.returns(Symbol) }
      def variant
        return :critical if budget.fully_funded? && budget.budget_limit_type == "PreventFurtherUsage"
        :warning
      end
    end
  end
end
