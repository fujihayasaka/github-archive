# typed: true
# frozen_string_literal: true

module Billing
  class PendingCycle

    delegate :data_pack_cost,
      :plan_cost,
      :marketplace_items_cost,
      :recurring_sponsorable_item_cost,
      :discount,
      to: :pricing

    sig { params(account: Billing::Types::Account, include_addons: T::Boolean).void }
    def initialize(account, include_addons: true)
      @account = account
      @include_addons = include_addons
    end

    # The seat count for the next billing cycle
    sig { returns(Integer) }
    def seats
      pending_cycle_change&.seats || account.seats
    end

    # The plan duration for the next billing cycle
    sig { returns(String) }
    def plan_duration
      pending_cycle_change&.plan_duration || account.plan_duration
    end
    alias_method :billing_interval, :plan_duration

    def data_packs
      pending_cycle_change&.data_packs || account.data_packs
    end

    # The plan for the next billing cycle
    #
    # Returns GitHub::Plan
    def plan
      pending_cycle_change&.plan || account.plan
    end

    def async_payment_amount
      GitHub::PrefillAssociations.prefill_associations(account, :customers)
      account.async_plan_subscription.then do |plan_sub|
        sub_items_promise = plan_sub ? plan_sub.async_active_subscription_items : Promise.resolve([])
        sub_items_promise.then { payment_amount }
      end
    end

    # Public: How much the user will pay for their next billing cycle.
    # Takes into account any discounts
    #
    # use_balance - Whether or not to include the current account balance in the
    #               payment_amount (optional; default false)
    # prorate     - Whether or not to prorate the payment amount for the amount
    #               of service remaining (optional; default false)
    #
    # Returns Money
    def payment_amount(use_balance: false, prorate: false)
      service_remaining = prorate ? account.subscription.sanitized_service_percent_remaining : 1

      discounted_price = pricing.prorate_to(service_remaining) do
        pricing.discounted
      end
      discounted_price + Billing::Money.new(use_balance ? balance_in_cents : 0)
    end

    # Public: When this pending cycle will be active, and any pending changes will be applied to the
    # account's subscription.
    #
    # Returns Date
    def active_on
      pending_cycle_change&.active_on || account.next_billing_date
    end

    # Public: Are there any changes being made to the next billing cycle
    #
    # including_free_trials: Boolean. Are you asking about free trial changes as
    # well?
    #
    # Returns Boolean
    def has_changes?(including_free_trials: true)
      changes = pending_subscription_item_changes
      changes = changes.non_free_trial unless including_free_trials
      !!(changing_data_packs? || has_plan_changes? || changes.present?)
    end

    # Public: Is the GitHub plan changing in the next billing cycle?
    #
    # Returns Boolean
    def has_plan_changes?
      !!(changing_duration? || changing_plan? || changing_seats?)
    end

    # Public: Discounted price the user will pay for their plan
    #
    # Returns Billing::Money
    def discounted_plan_price
      pricing.discounted_plan_cost + pricing.discounted_seat_cost
    end

    # Public: Discounted price the user will pay for their data packs
    #
    # Returns Billing::Money
    def discounted_data_packs_price
      pricing.discounted_data_pack_cost + Billing::Money.new(balance_in_cents)
    end

    def downgrading?
      (changing_plan? || changing_seats?)
    end

    delegate \
      :changing_data_packs?,
      :changing_duration?,
      :changing_plan?,
      :changing_seats?,
      :async_user,
      to: :pending_cycle_change,
      allow_nil: true

    delegate \
      :pending_subscription_item_changes,
      to: :account

    attr_reader :account

    private

    delegate \
      :pending_cycle_change,
      :plan_subscription,
      to: :account

    # Internal: Pricing for the next billing cycle
    #
    # Returns Billing::Pricing
    def pricing
      @price ||= Billing::Pricing.new(
        account: account,
        plan_subscription: plan_subscription,
        plan: plan,
        seats: seats,
        plan_duration: plan_duration,
        data_packs: data_packs,
        coupon: account.coupon,
        subscription_items: pending_subscription_item_changes.to_a,
        include_addons: @include_addons,
        plan_annual_discount: account.annual_discount_allowed?(plan: plan, billing_cycle: plan_duration, target_date: active_on),
      )
    end

    def balance_in_cents
      plan_subscription&.balance.to_f * 100
    end
  end
end
