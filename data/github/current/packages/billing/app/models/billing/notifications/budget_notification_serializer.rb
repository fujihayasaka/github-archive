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

      sig { returns(T.nilable(Integer)) }
      def month
        return nil unless FeatureFlag.vexi.enabled?(:billing_budget_threshold_notification_month_year_fields, owner, default: false)
        result.context[:month]
      end

      sig { returns(T.nilable(Integer)) }
      def year
        return nil unless FeatureFlag.vexi.enabled?(:billing_budget_threshold_notification_month_year_fields, owner, default: false)
        result.context[:year]
      end

      sig { override.returns(String) }
      def usage_reset_date_text
        # Check for valid month and year (must be present and greater than 0)
        if month&.positive? && year&.positive?
          # Create a date for the first day of the next month (when budget resets)
          next_month_date = Date.new(T.must(year), T.must(month), 1).next_month
          "This budget applies to usage in #{Date::MONTHNAMES[T.must(month)]} #{year}. Your budget period resets on #{next_month_date.to_formatted_s(:long)}"
        else
          # Fall back to the parent implementation
          super
        end
      end
    end
  end
end
