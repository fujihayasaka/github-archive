# typed: strict
# frozen_string_literal: true

module Billing
  module PlanSubscription::SynchronizationStatus
    extend T::Helpers

    requires_ancestor { ::Billing::PlanSubscription }

    sig { returns(T.nilable(::Billing::Zuora::Subscription)) }
    def fetched_external_subscription
      @fetched_external_subscription ||= T.let(external_subscription, T.nilable(::Billing::Zuora::Subscription))
    end

    # Public: Is this PlanSubscription synchronized with its counterpart on Zuora?
    sig { returns(T::Boolean) }
    def synchronized?
      return false unless fetched_external_subscription

      plan_synchronized? &&
      plan_duration_synchronized? &&
      seats_synchronized? &&
      asset_packs_synchronized? &&
      discount_synchronized? &&
      balance_synchronized? &&
      next_billing_date_synchronized? &&
      subscription_items_synchronized?
    end

    sig { returns(T::Boolean) }
    def plan_synchronized?
      if zuora_subscription? && T.must(fetched_external_subscription).plan.nil?
        plan.free? || plan.free_with_addons?
      else
        plan == T.must(fetched_external_subscription).plan
      end
    end

    sig { returns(T::Boolean) }
    def plan_duration_synchronized?
      return false unless fetched_external_subscription = self.fetched_external_subscription
      plan_duration == fetched_external_subscription.plan_duration
    end

    sig { returns(T::Boolean) }
    def seats_synchronized?
      return true unless plan.per_seat?
      return false unless fetched_external_subscription = self.fetched_external_subscription

      seat_count == fetched_external_subscription.seats
    end

    sig { returns(T::Boolean) }
    def asset_packs_synchronized?
      return false unless fetched_external_subscription = self.fetched_external_subscription

      data_packs == fetched_external_subscription.data_packs
    end

    sig { returns(T::Boolean) }
    def discount_synchronized?
      return false unless fetched_external_subscription = self.fetched_external_subscription

      coupon_amount.to_d == fetched_external_subscription.discount.to_d
    end

    sig { returns(T::Boolean) }
    def balance_synchronized?
      return false unless fetched_external_subscription = self.fetched_external_subscription
      #Ensure both sides are BigDecimal because normally balance will be BigDecimal
      fetched_balance = fetched_external_subscription.balance
      if fetched_balance.is_a?(Float)
        balance.to_d == fetched_balance.to_d(5)
      else
        balance.to_d == fetched_balance.to_d
      end
    end

    sig { returns(T::Boolean) }
    def next_billing_date_synchronized?
      return false unless fetched_external_subscription = self.fetched_external_subscription

      billed_on == fetched_external_subscription.next_billing_date
    end

    sig { returns(T::Boolean) }
    def subscription_items_synchronized?
      return false unless fetched_external_subscription = self.fetched_external_subscription

      fetched_external_subscription.subscription_items_synchronized?(active_subscription_items.to_a)
    end

    sig { returns(T::Hash[Symbol, T::Boolean]) }
    def sync_breakdown
      return {} unless fetched_external_subscription

      {
        asset_packs_synchronized: asset_packs_synchronized?,
        balance_synchronized: balance_synchronized?,
        discount_synchronized: discount_synchronized?,
        next_billing_date_synchronized: next_billing_date_synchronized?,
        plan_duration_synchronized: plan_duration_synchronized?,
        plan_synchronized: plan_synchronized?,
        seats_synchronized: seats_synchronized?,
        subscription_items_synchronized: subscription_items_synchronized?,
      }
    end

    sig { returns(Integer) }
    def seat_count
      plan.business? ? additional_seats : seats
    end
  end
end
