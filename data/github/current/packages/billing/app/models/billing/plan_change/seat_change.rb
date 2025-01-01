# typed: true
# frozen_string_literal: true

module Billing
  # Models changing seat count on a per seat organization. Handles both upgrades
  # (charges) and downgrades (refunds).
  class PlanChange::SeatChange < PlanChange
    extend T::Sig

    include ProrationMath

    # Public: Creates a PlanChange::SeatChange that models adding or removing
    # seats from a per seat account.
    #
    # account - User/Organization account.
    # seats   - Integer new number of seats.

    # Returns a PlanChange::SeatChange.
    attr_accessor :coupon_discount

    def initialize(account, seats:, plan_and_seat_cost_only: false)
      @account = account
      old_subscription = Subscription.for_account(account)
      @coupon_discount = account.coupon.try(:discount)
      @plan_and_seat_cost_only = plan_and_seat_cost_only
      @discount_allowed = account&.annual_discount_allowed?
      new_subscription = Subscription.based_on_subscription old_subscription, \
                          seats: seats,
                          coupon_discount: coupon_discount,
                          plan_annual_discount: @discount_allowed
      super(old_subscription, new_subscription, plan_and_seat_cost_only: plan_and_seat_cost_only)

      @pricing = Billing::Pricing.new(account: account, plan_annual_discount: @discount_allowed)
    end

    # Public: String human unit price of each seat for the new plan's duration.
    #
    # Returns String - human-readable price
    def human_unit_price
      "#{unit_price.format(no_cents: true)}/#{new_subscription.duration} each"
    end

    # Public: Integer days of service remaining in old subscription.
    def service_days_remaining
      old_subscription.service_days_remaining
    end

    # Public: Is this a prorated purchase
    def prorated_purchase?
      old_subscription.seats > 0
    end

    # Public: Returns true if there's a coupon discount
    def coupon_discount?
      @pricing.discount.positive?
    end

    # Public: Money list price of the new seat count prorated for the remaining
    # days of service in the current billing cycle.
    #
    # Returns Money price
    def list_price
      prorated_price(:list)
    end

    # Public: Money price to change to the new seat count prorated for the remaining
    # service and including any discounts.
    #
    # Returns Money price
    def discounted_price
      prorated_price(:final)
    end

    # Public: Price to change to the new seat count, including any discounts and
    # credits. Positive if the customer owes us, negative if there's credit
    # remaining.
    #
    # Returns Money price
    def final_price
      prorated_price(:final) + balance
    end

    # Public: Money payment amount required to change to the new seat count
    # taking into account discounts and credits, with a lower bound of 0.
    #
    # Returns Money price
    def payment_amount
      [final_price, Billing::Money.new(0)].max
    end

    # Public: Money credit used to change to the new seat count with a lower
    # bound of 0.
    sig { returns(Billing::Money) }
    def credit_used
      used = [discounted_price, balance.abs].min
      [used, Billing::Money.new(0)].max
    end

    # Public: Money credit remaining after changing to the new seat count.
    #
    # Returns Money credit remaining
    def credit_remaining
      [final_price, Billing::Money.new(0)].min.abs
    end

    def unit_price
      @pricing.plan_cost
    end

    def renewal_price
      if @plan_and_seat_cost_only
        @renewal_price ||= renewal_subscription_without_discount.discounted_plan_and_seat_cost
      else
        @renewal_price ||= renewal_subscription_without_discount.discounted_price
      end
    end

    def current_price
      if @plan_and_seat_cost_only
        @current_price ||= renewal_subscription_maybe_discount.discounted_plan_and_seat_cost
      else
        @current_price ||= renewal_subscription_maybe_discount.discounted_price
      end
    end

    private

    # Internal: Money price prorated for remaining days in current service period.
    def prorated_price(type)
      case type
      when :list
        price_for_duration = new_subscription.undiscounted_monthly_price * old_subscription.duration_in_months
        old_price_for_duration = old_subscription.undiscounted_monthly_price * old_subscription.duration_in_months
      when :final
        price_for_duration = new_subscription.discounted_monthly_price * old_subscription.duration_in_months
        old_price_for_duration = old_subscription.discounted_monthly_price * old_subscription.duration_in_months
      end

      price_difference = price_for_duration - old_price_for_duration
      if new_subscription.plan_annual_discount
        discounted_annual_price_difference = price_difference * new_subscription.annual_discount_multiplier
        price_difference = price_difference - discounted_annual_price_difference
      end
      # Prorate the price, but if this is an upgrade from free, special case it
      # and just return the full price.  The Subscription model doesn't model
      # non-prorated purchases as service_percent_remaining is always < 100%
      if prorated_purchase?
        prorate(price_difference, old_subscription.service_percent_remaining)
      else
        price_for_duration
      end
    end

    def renewal_subscription_without_discount
      @renewal_subscription_without_discount ||= Subscription.based_on_subscription new_subscription, \
        seats: seats,
        coupon_discount: coupon_discount,
        plan_annual_discount: false
    end

    def renewal_subscription_maybe_discount
      @renewal_subscription_maybe_discount ||= Subscription.based_on_subscription new_subscription, \
        seats: seats,
        coupon_discount: coupon_discount,
        plan_annual_discount: @discount_allowed
    end
  end
end
