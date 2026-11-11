# typed: strict
# frozen_string_literal: true

module Stafftools
  module Billing
    class UpdateZuoraAccountInfoComponent < ApplicationComponent

      sig { params(customer: Customer, button_text: String, button_scheme: Symbol, button_float: T.nilable(Symbol)).void }
      def initialize(customer:, button_text: "Update Zuora information", button_scheme: :danger, button_float: :right)
        @customer = customer
        @button_text = button_text
        @button_scheme = button_scheme
        @button_float = button_float
      end

      sig { returns(T::Boolean) }
      def render?
        customer.present? && plan_subscription.present?
      end

      delegate :zuora_account_id, :zuora_account_number, to: :customer, allow_nil: true
      delegate :zuora_subscription_id, :zuora_subscription_number, to: :plan_subscription, allow_nil: true

      sig { returns(String) }
      def entity_name
        billable_owner&.display_login
      end

      sig { returns(Integer) }
      def customer_id
        customer.id
      end

      sig { returns(String) }
      attr_reader :button_text

      sig { returns(Symbol) }
      attr_reader :button_scheme

      sig { returns(T.nilable(Symbol)) }
      attr_reader :button_float

      private

      sig { returns(Customer) }
      attr_reader :customer

      sig { returns(T.nilable(T.any(::User, Business))) }
      memoize def billable_owner
        customer.billable_owner
      end

      sig { returns(T.nilable(T.any(::Billing::PlanSubscription, ::Billing::SalesServePlanSubscription))) }
      memoize def plan_subscription
        billable_owner = self.billable_owner
        return billable_owner.sales_serve_plan_subscription if billable_owner.is_a?(Business) && billable_owner.invoiced?
        billable_owner&.plan_subscription
      end
    end
  end
end
