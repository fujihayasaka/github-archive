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

      sig { params(actor: User).returns(T.nilable(Billing::Notifications::CombinedBudgetThresholdBanner)) }
      def combined_budget_threshold_banner(actor:)
        all_banners = budget_threshold_banners(actor: actor)
        variant_hierarchy = [:critical, :warning]

        variant_hierarchy.each do |variant|
          variant_banner = combine_banners_by_variant(all_banners, variant)
          return variant_banner if variant_banner
        end

        nil
      end

      private

      attr_reader :owner, :context, :actor

      sig do
        params(
          all_banners: T::Array[Billing::Notifications::BudgetThresholdBanner],
          variant: Symbol
        ).returns(T.nilable(Billing::Notifications::CombinedBudgetThresholdBanner))
      end
      def combine_banners_by_variant(all_banners, variant)
        variant_banners = all_banners.select { |banner| banner.variant == variant }
        if variant_banners.length == 0
          nil
        else
          Billing::Notifications::CombinedBudgetThresholdBanner.new(
            budget_threshold_banners: variant_banners,
            variant: variant
          )
        end
      end

      sig { returns(T::Array[Billing::Notifications::BudgetNotification]) }
      def budgets_with_notification
        budgets.map do |budget|
          BudgetNotification.new(budget:, context:, actor:)
        end.select(&:has_result?)
      end

      sig { returns(T::Array[Billing::Platform::Api::Budget]) }
      def budgets
        response = billing_platform_client.get_alertable_budget_state_info(customer_id: owner.customer.id)
        return [] if response.is_a?(Billing::Platform::Api::Error)
        budgets = response[:budgets]
        if @owner.is_a?(Business) && @actor.present?
          budgets = filter_budget_by_role(budgets: budgets, current_user: @actor, entity: @owner)
        end
        budgets
      end

      sig { returns(Billing::Platform::Api::Client) }
      def billing_platform_client
        Billing::Platform::Api::Client.new(timeout: 3)
      end
    end
  end
end
