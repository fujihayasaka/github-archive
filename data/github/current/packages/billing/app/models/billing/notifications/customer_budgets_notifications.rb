# typed: true
# frozen_string_literal: true

module Billing
  module Notifications
    class CustomerBudgetsNotifications
      include Billing::Platform::Api::Utils

      sig do
        params(
          owner: T.any(User, Organization, Business),
          context: T.nilable(T.any(User, Organization, Business, Repository)),
          actor: T.nilable(User)
        ).void
      end
      def initialize(owner:, context: nil, actor: nil)
        @owner = owner
        @context = context || owner
        @actor = actor
      end

      sig { returns(T::Array[Billing::Notifications::BudgetNotification]) }
      def budget_notifications
        @budget_notifications ||= budgets_with_notification
      end

      sig { params(actor: User).returns(T::Array[Billing::Notifications::BudgetThresholdBanner]) }
      def budget_threshold_banners(actor:)
        budget_notifications.map do |budget_notification|
          BudgetThresholdBanner.new(budget_notification: budget_notification, actor: actor)
        end.select(&:visible?)
      end

      private

      attr_reader :owner, :context, :actor

      sig { returns(T::Array[Billing::Notifications::BudgetNotification]) }
      def budgets_with_notification
        budgets.map do |budget|
          BudgetNotification.new(budget:, context:, actor:)
        end.select(&:has_result?)
      end

      sig { returns(T::Array[Billing::Platform::Api::Budget]) }
      def budgets
        response = billing_platform_client.get_all_budgets(customer_id: owner.customer.id)
        return [] if response.is_a?(Billing::Platform::Api::Error)
        budgets = response[:budgets]
        if @owner.is_a?(Business) && @actor.present?
          budgets = filter_budget_by_role(budgets: budgets, current_user: @actor, entity: @owner)
        end
        budgets
      end

      sig { returns(Billing::Platform::Api::Client) }
      def billing_platform_client
        Billing::Platform::Api::Client.new
      end
    end
  end
end
