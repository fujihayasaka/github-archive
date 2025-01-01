# typed: strict
# frozen_string_literal: true

module Platform
  module Interfaces
    module Billable
      extend T::Helpers

      requires_ancestor { Platform::Objects::Base }

      include Platform::Interfaces::Base
      include Platform::Interfaces::FeatureFlaggable
      description "Entities that can be billed for their subscription."
      visibility :internal

      field :total_available_seats, Integer, "The number of seats for this account including bundled seats that are not in use.", visibility: :internal, null: false

      field :has_unlimited_seats, Boolean, "Is this account on a free trial?", method: :has_unlimited_seats?, visibility: :internal, null: false

      field :is_invoiced, Boolean, "Is the account billed through invoices?", method: :async_invoiced?, visibility: :internal, null: false

      field :subscription, Objects::Subscription, description: "Return the associated billing subscription for the user.", null: false
      sig { returns(Promise[::Billing::PlanSubscription]) }
      def subscription
        object.async_plan_subscription.then do |subscription|
          subscription || ::Billing::PlanSubscription.new(user: object)
        end
      end

      field :payment_method, Objects::PaymentMethod, description: "The user's default payment method", null: true
      sig { returns(Promise[T.nilable(PaymentMethod)]) }
      def payment_method
        object.async_customer.then do |customer|
          customer && customer.async_payment_method
        end
      end

      field :billing_transactions, Connections::BillingTransaction, visibility: :internal, description: "Transaction records for all billing events tied to an account.", null: true, connection: true do
        argument :sales, Boolean, "Filter out refunds and transactions without a payment associated.", required: false
        argument :descending, Boolean, "Return the transactions in descending order.", required: false
      end
      sig do
        params(
          sales: T.nilable(T::Boolean),
          descending: T.nilable(T::Boolean)
        ).returns(T::Enumerable[::Billing::BillingTransaction])
      end
      def billing_transactions(sales: false, descending: false)
        transactions = object.billing_transactions
        transactions = transactions.sales if sales
        transactions = transactions.descending if descending
        transactions.scoped
      end

      field :current_credit, Scalars::Money, "The current credit on this account", visibility: :internal, null: true
      sig { returns(Promise[::Billing::Money]) }
      def current_credit
        object.async_plan_subscription.then do
          Billing::Money.new([object.credit, 0].max * 100)
        end
      end
    end
  end
end
