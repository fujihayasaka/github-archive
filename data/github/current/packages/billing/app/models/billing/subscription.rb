# typed: true
# frozen_string_literal: true

module Billing
  # Represents a subscription to a (paid) plan.
  class Subscription
    include ProrationMath
    FREE_TRIAL_LENGTH = 14.days

    # Public: New GitHub::Plan
    attr_reader :plan

    # Public: New number of seats
    attr_reader :seats

    # Public: New number of data packs
    attr_reader :data_packs

    # Public: New subscription items
    attr_reader :subscription_items

    # Public: New coupon discount
    attr_reader :coupon_discount

    # Public: Date the service starts on.
    attr_reader :service_starts_on

    # Public: Date the service ends on which is 1 day before the next date the
    # account should be billed.
    attr_reader :service_ends_on

    # Public: Date the user will be next billed.
    attr_reader :service_next_bills_on

    # Public: Integer service days remaining until service ends.
    attr_reader :service_days_remaining

    # Public: The percentage of service remaining on this subscription. If the
    # subscription has 25% left, this will return 0.25.  This will never be
    # greater than 100% and other than edge cases where the current date is
    # *before* the service start date, it should fall below 100%.  This reflects
    # Braintree/Zuora's model that once you start a subscription, you have
    # already used the first day of service.
    attr_reader :service_percent_remaining

    # Public: The amount of service remaining as a Rational; see
    # :service_percent_remaining for more details
    attr_reader :service_remaining

    # Public: String duration in words (either 'month' or 'year').
    attr_reader :duration

    # Public: Integer full term intended duration of this subscription in months.
    # Usually 1 or 12 to support monthly and yearly plans.
    attr_reader :duration_in_months

    # Public: Integer full duration of this subscription in days. This will be the
    # number of days in the month for monthly subscriptions and the number of
    # days in the year for yearly subscriptions.
    attr_reader :duration_in_days

    # Public: Money balance on the account. Negative balances are a credit.
    attr_reader :balance

    # Public: A boolean indicating whether or not to apply the anual discount
    attr_reader :plan_annual_discount

    # Public: Creates a subscription to a plan for a ranges of dates.
    #
    # plan                 - A GitHub::Plan (optional).
    # seats                - Integer new total seats (optional, default: 0).
    # data_packs           - Integer new data packs (optional, default: 0).
    # subscription_items   - Array of SubscriptionItems (optional).
    # coupon_discount      - Integer or float coupon discount per month
    # plan_annual_discount - Boolean indicating whether or not to apply the anual discount

    #                      (optional, default: 0).
    # starts             - Date service starts on (optional).
    # ends               - Date service ends on (optional).
    # duration_in_months - Integer duration of subscription in months (optional).
    # balance            - BigDecimal account balance in dollars
    # active_on          - Date the service becomes active if there's a trial(optional)
    #
    # Returns a new Subscription.
    def initialize(plan: nil, seats: 0, data_packs: 0, subscription_items: nil, coupon_discount: nil, plan_annual_discount: false, starts: nil, ends: nil, duration_in_months: nil, balance: 0, active_on: GitHub::Billing.today)
      @plan = plan
      @seats = seats
      @data_packs = data_packs
      @subscription_items = subscription_items.to_a
      @coupon_discount = coupon_discount
      @plan_annual_discount = plan_annual_discount

      @duration_in_months = duration_in_months || 1
      @duration = @duration_in_months == 1 ? User::BillingDependency::MONTHLY_PLAN : User::BillingDependency::YEARLY_PLAN

      if !ends
        @service_starts_on = starts || GitHub::Billing.today
        @service_next_bills_on = service_starts_on + @duration_in_months.months
        @service_ends_on = service_next_bills_on - 1.day
      else
        @service_ends_on = ends
        @service_next_bills_on = service_ends_on + 1.day
        @service_starts_on = starts || service_next_bills_on - @duration_in_months.months
      end

      @duration_in_days = (service_next_bills_on - service_starts_on).to_i
      @service_days_remaining = [(service_ends_on - active_on).to_i, 0].max
      @service_remaining = Rational(service_days_remaining, @duration_in_days)
      @service_percent_remaining = [(service_days_remaining / @duration_in_days.to_f), 1.0].min
      @balance = Billing::Money.new(balance * 100)
    end

    # Public: Creates a new Subscription based on an existing Subscription.
    #
    # subscription               - The Subscription to base the new Subscription on.
    # plan                       - A GitHub::Plan
    # seats                      - Integer new total seats
    # coupon_discount            - Integer or float coupon discount per month
    #
    # Returns a Subscription.
    def self.based_on_subscription(subscription, seats:, coupon_discount:, plan_annual_discount: false, data_packs: subscription&.data_packs)
      raise ArgumentError, "subscription can't be nil" unless subscription

      new \
        plan: subscription.plan,
        seats: seats,
        data_packs: data_packs,
        subscription_items: subscription.subscription_items,
        coupon_discount: coupon_discount,
        plan_annual_discount: plan_annual_discount,
        starts: subscription.service_starts_on,
        ends: subscription.service_ends_on,
        duration_in_months: subscription.duration_in_months,
        balance: subscription.balance
    end

    # Public: Creates a new Subscription for the requested account.
    #
    # account                    - User/Organization account to create a subscription for.
    # plan                       - A GitHub::Plan (optional, defaults to plan on account).
    # seats                      - Integer new total seats (optional, defaults to seats on account.
    # asset_packs                - Integer new asset packs (optional, defaults to asset packs on account).
    # coupon_discount            - Integer or float coupon discount per month
    #                              (optional, default: 0).
    # duration_in_months         - Integer duration in months (optional).
    # subscription_items         - Array of SubscriptionItems (optional).
    # plan_subscription          - Billing::PlanSubscription to use for the given account; optional, defaults to
    #                              general-purpose plan subscription for the account
    #
    # Returns a Subscription.
    def self.for_account(account, plan: nil, seats: nil, asset_packs: nil, coupon_discount: nil, duration_in_months: nil, subscription_items: nil, plan_subscription: nil, balance: nil)
      raise ArgumentError, "account can't be nil" unless account
      service_ends_on = if duration_in_months && duration_in_months != account.plan_duration_in_months
        nil
      elsif plan_subscription && plan_subscription.sponsors_purpose?
        account.next_sponsors_billing_date
      elsif (billed_on = account.billed_on).present?
        billed_on.to_date - 1.day
      else
        nil
      end

      duration = \
      if duration_in_months
        duration_in_months == 1 ? User::BillingDependency::MONTHLY_PLAN : User::BillingDependency::YEARLY_PLAN
      else
        account.plan_duration
      end
      plan_annual_discount = duration_in_months == 12 && account.annual_discount_allowed?(plan: plan, billing_cycle: User::BillingDependency::YEARLY_PLAN)

      # If there's a coupon on the account, use that discount
      pricing = Billing::Pricing.new(
        account: account,
        plan: plan,
        plan_duration: duration,
      )
      coupon_discount ||= account.coupon&.discount if pricing.discount.positive?

      plan_subscription ||= account.plan_subscription
      balance ||= plan_subscription&.balance || 0
      customer ||= plan_subscription&.customer
      # For the purposes of billing/pricing, subscription items on other plan subscriptions
      # still be need to be included. The customer is billed, not the specific subscription.
      subscription_items ||= customer&.active_subscription_items

      new(
        plan: plan || account.plan,
        seats: seats || account.seats,
        data_packs: asset_packs || account.data_packs,
        subscription_items: subscription_items,
        coupon_discount: coupon_discount,
        plan_annual_discount: plan_annual_discount,
        ends: service_ends_on,
        duration_in_months: duration_in_months || account.plan_duration_in_months,
        balance: balance,
      )
    end

    def discounted_monthly_price
      pricing.monthly { |p| p.discounted }
    end

    def undiscounted_monthly_price
      pricing.monthly { |p| p.undiscounted }
    end

    def undiscounted_yearly_price
      pricing.yearly { |p| p.undiscounted }
    end

    # Public: Money price of subscriptions including discounts.
    #
    # prorate - Boolean. Should the price be prorated based on the service remaining? Default false.
    #
    # Returns a Money amount
    def discounted_price(prorate: false)
      service_remaining = prorate ? sanitized_service_percent_remaining : 1

      pricing.prorate_to(service_remaining) do
        pricing.discounted
      end
    end

    def undiscounted_price
      pricing.undiscounted
    end

    def discount
      pricing.discount
    end

    def total_subscription_items_price
      pricing.marketplace_item_cost + pricing.recurring_sponsorable_item_cost
    end

    def discounted_github_items_price
      pricing.discounted - pricing.marketplace_item_cost
    end

    # Public: Money price of remaining service.
    #
    # use_balance - Boolean whether to use the account balance (optional, default: false)
    #
    # Returns a Money amount
    def price_of_remaining_service
      discounted_price(prorate: true)
    end

    # Public: Non-zero service percent remaining
    #
    # Returns a Float
    def sanitized_service_percent_remaining
      service_percent_remaining.zero? ? 1.0 : service_percent_remaining
    end

    # Public: If this subscription started a free trial today, when would it
    # end?
    def free_trial_end_date
      GitHub::Billing.today + FREE_TRIAL_LENGTH
    end

    def post_free_trial_bill_date
      next_bill_date_after(date: free_trial_end_date)
    end

    def next_bill_date_after(date:)
      next_date = service_next_bills_on
      duration_in_months = @duration_in_months.months
      until next_date > date
        next_date += duration_in_months
      end
      next_date
    end

    def yearly_cost_in_cents
      plan_annual_discount ? plan.yearly_cost_in_cents_with_discount : plan.yearly_cost_in_cents
    end

    def annual_discount_multiplier
      plan.yearly_discount_percentage / 100
    end

    def discounted_plan_and_seat_cost
      pricing.discounted_plan_and_seat_cost
    end

    def plan_and_seat_cost
      pricing.plan_and_seat_cost
    end

    private

    def pricing
      @pricing ||= Billing::Pricing.new(
        plan: plan,
        seats: seats,
        data_packs: data_packs,
        subscription_items: subscription_items,
        plan_duration: duration,
        discount: coupon_discount.to_f,
        plan_annual_discount: plan_annual_discount,
      )
    end
  end
end
