# typed: true
# frozen_string_literal: true

module Billing
  module Notifications
    class BudgetNotification
      include GitHub::Memoizer

      attr_reader :result, :owner, :billable_owner, :budget, :context, :actor

      sig do
        params(
          budget: Billing::Platform::Api::Budget,
          context: T.nilable(T.any(User, Organization, Business, Repository)),
          actor: T.nilable(User)
        ).void
      end
      def initialize(budget:, context: nil, actor: nil)
        @budget = budget
        @owner = budget.owner
        @context = context || owner
        @billable_owner = owner&.billable_owner
        @result = threshold_result
        @actor = actor
      end

      sig { returns(T.nilable(Billing::Notifications::BudgetNotificationSerializer)) }
      memoize def serialize
        return nil unless has_result?

        BudgetNotificationSerializer.new(self)
      end

      alias_method :highest_priority_notification, :serialize

      sig { returns(T::Boolean) }
      def has_result?
        result.present?
      end

      sig { returns(Billing::Platform::Api::Budget) }
      def active_budget
        budget
      end

      private

      sig { returns(T.nilable(Billing::Notifications::Result)) }
      def threshold_result
        return unless budget.owner.present?
        return unless budget.visible_to?(context)
        return unless budget.current_amount.positive?
        return unless budget.alert_enabled?
        return unless budget.threshold_alertable?
        return if billable_owner.plan.legacy?

        Result.new(
          value: budget.current_percentage,
          threshold: budget.threshold_percentage,
          tags: [budget.product_name, budget.pricing_target_type, budget.budget_limit_type],
          context: {
            used: budget.current_amount,
            available: budget.target_amount
          }
        )
      end
    end
  end
end
