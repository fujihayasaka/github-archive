# typed: strict
# frozen_string_literal: true

module Stafftools
  module Billing
    module Customers
      class HealthDashboardComponent < ApplicationComponent
        sig { params(customer: Customer, payment_method: T.nilable(PaymentMethod), plan_subscriptions: T.untyped).void }
        def initialize(customer:, payment_method:, plan_subscriptions:)
          @customer = customer
          @payment_method = payment_method
          @plan_subscriptions = plan_subscriptions
        end

        private

        sig { returns(Customer) }
        attr_reader :customer

        sig { returns(T.nilable(PaymentMethod)) }
        attr_reader :payment_method

        sig { returns(T.untyped) }
        attr_reader :plan_subscriptions

        sig { returns(T::Boolean) }
        def has_valid_payment?
          return false unless payment_method.present?

          T.must(payment_method).valid_payment_token? || false
        end

        sig { returns(T::Boolean) }
        def has_active_subscription?
          plan_subscriptions.any?
        end

        sig { returns(T::Boolean) }
        def has_zuora_account?
          customer.zuora_account_id.present?
        end

        sig { returns(T::Boolean) }
        def is_locked?
          customer.locked_at.present?
        end

        sig { returns(T::Boolean) }
        def overall_healthy?
          return true if customer.billing_type == "invoice"

          has_valid_payment? && has_active_subscription? && !is_locked?
        end

        sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
        def health_checks
          checks = []

          checks << {
            label: "Payment Method",
            icon: "credit-card",
            ok: has_valid_payment?,
            detail: has_valid_payment? ? "Valid #{payment_method&.payment_processor_type} payment on file" : "No valid payment method",
          }

          checks << {
            label: "Plan Subscription",
            icon: "package",
            ok: has_active_subscription?,
            detail: has_active_subscription? ? "#{plan_subscriptions.size} active subscription(s)" : "No active subscriptions",
          }

          checks << {
            label: "Zuora Account",
            icon: "sync",
            ok: has_zuora_account?,
            detail: has_zuora_account? ? "Linked (#{customer.zuora_account_id})" : "Not linked to Zuora",
          }

          checks << {
            label: "Billing Status",
            icon: "shield-check",
            ok: !is_locked?,
            detail: is_locked? ? "Billing LOCKED since #{customer.locked_at}" : "Active & unlocked",
          }

          checks
        end
      end
    end
  end
end
