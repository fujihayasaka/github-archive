# typed: true
# frozen_string_literal: true

module Billing
  # Models changing between any two arbitrary subscriptions and provides the
  # total prorated price associated with making the change.
  class PlanChange
    include ProrationMath

    attr_reader :old_subscription, :new_subscription
    delegate :service_percent_remaining, to: :old_subscription
    delegate :seats, to: :new_subscription

    # Creates a PlanChange to model the prices and discounts associated
    # with changing from one subscription to another.
    #
    # old_subscription - The old Subscription.
    # new_subscription - The new Subscription.
    #
    # Returns a new PlanChange.
    def initialize(old_subscription, new_subscription, starting_new_subscription: nil, plan_and_seat_cost_only: false)
      @old_subscription = old_subscription
      @new_subscription = new_subscription
      @starting_new_subscription = starting_new_subscription
      @plan_and_seat_cost_only = plan_and_seat_cost_only
    end

    # Internal: The price difference between the new and old subscriptions.
    #
    # github_only - Boolean. Do you want the price difference to only include
    #               GitHub costs (i.e. exclude marketplace costs)? Default false.
    #
    def price_difference(github_only: false)
      if @plan_and_seat_cost_only
        new_subscription_discounted_plan_and_seat_cost - old_subscription.discounted_plan_and_seat_cost
      elsif github_only
        new_subscription_discounted_github_items_price - old_subscription.discounted_github_items_price
      else
        new_subscription_discounted_price - old_subscription.discounted_price
      end
    end

    # Public: Number of seats on the old subscription
    #
    # Returns Integer
    def old_seats
      old_subscription.seats
    end

    # Public: Number of seats excluding base seats
    #
    # Returns Integer
    def additional_seats
      new_subscription.seats - new_subscription.plan.base_units
    end

    def old_additional_seats
      old_subscription.seats - old_subscription.plan.base_units
    end

    def seats_delta
      return 0 unless new_subscription.plan.per_seat?

      if changing_plan?
        additional_seats
      else
        additional_seats - old_additional_seats
      end
    end

    def data_packs_delta
      new_subscription.data_packs - old_subscription.data_packs
    end

    def subscription_items_delta
      new_subscription.subscription_items.map do |item|
        if free_trial_ending?(item)
          item
        else
          delta = subscription_item_quantity_delta(item)
          item.dup.tap { |item| item.quantity = delta } unless delta.zero?
        end
      end.compact
    end

    # Public - Total price for all subscription items based on new subscription
    #
    # Returns Money
    def total_subscription_items_price
      new_subscription.total_subscription_items_price
    end

    # Public - Total price for all GitHub items (i.e. seats, data packs, plan)
    #
    # Returns Money
    def github_items_price
      final_price - total_subscription_items_price
    end

    # Public: Money prorated final price to change from the old subscription to the new
    # subscription.
    #
    # github_only - Boolean. Do you want the price to only include
    #               GitHub costs (i.e. exclude marketplace costs)? Default false.
    #
    # use_balance - Boolean use the balance on the account. (optional. Default false)
    #
    # Returns Money
    def final_price(github_only: false, use_balance: false)
      price = if starting_new_subscription?
        renewal_price(github_only: github_only)
      else
        prorate \
          price_difference(github_only: github_only),
          old_subscription.sanitized_service_percent_remaining
      end
      use_balance ? price + balance : price
    end

    # Public: Money renewal price for a full term of the new subscription.
    #
    # github_only - Boolean. Do you want the price to only include
    #               GitHub costs (i.e. exclude marketplace costs)? Default false.
    def renewal_price(github_only: false)
      if @plan_and_seat_cost_only
        new_subscription_discounted_plan_and_seat_cost
      elsif github_only
        new_subscription_discounted_github_items_price
      else
        new_subscription_discounted_price
      end
    end

    # Public: Money list price of renewal (before discounts).
    def renewal_list_price
      return new_subscription.plan_and_seat_cost if @plan_and_seat_cost_only
      new_subscription.undiscounted_price
    end

    # Public: If creating a new subcription or updating an existing subscription
    #
    # Return Boolean
    def starting_new_subscription?
      @starting_new_subscription || upgrading_from_free? || changing_duration?
    end

    # Public: Only changing the plan duration and not the plan?
    #
    # Returns boolean
    def duration_change_only?
      old_subscription.plan == new_subscription.plan && changing_duration?
    end

    def balance
      [old_subscription.balance, Billing::Money.zero].min
    end

    def changing_plan?
      old_subscription.plan != new_subscription.plan
    end

    def changing_duration?
      old_subscription.duration != new_subscription.duration
    end

    def upgrading_from_free?
      old_subscription.plan.free?
    end

    # Public: The prorated price for a marketplace purchase including a credit when upgrading to a new plan
    #
    # Returns Billing::Money
    def prorated_mp_price_for(subscription_item:, service_percent_remaining:)
      old_item = old_subscription.subscription_items.detect do |old_item|
        subscription_item.listing.id == old_item.listing.id
      end

      price = subscription_item.price(service_remaining: service_percent_remaining)
      return price unless old_item && old_item.subscribable != subscription_item.subscribable

      price -= prepaid_amount_for(subscription_item.user, old_item.subscribable)
      Billing::Money.new([0, price].max)
    end

    # Public: Unit price of the new subscription in Money for the new plan's
    # duration. For per seat plans, this is the unit price of 1 seat.
    def unit_price
      if new_subscription.duration == User::BillingDependency::MONTHLY_PLAN
        Billing::Money.new(new_subscription.plan.unit_cost * 100)
      else
        Billing::Money.new(new_subscription.yearly_cost_in_cents)
      end
    end

    def subscription_item(subscribable:, quantity: nil)
      item = new_subscription.subscription_items.detect { |item| item.subscribable == subscribable }
      item.quantity = quantity if quantity
      item
    end

    private

    def new_subscription_discounted_github_items_price
      @new_subscription_discounted_github_items_price ||= new_subscription.discounted_github_items_price
    end

    def new_subscription_discounted_price
      @new_subscription_discounted_price ||= new_subscription.discounted_price
    end

    def new_subscription_discounted_plan_and_seat_cost
      @new_subscription_plan_and_seat_cost ||= new_subscription.discounted_plan_and_seat_cost
    end

    # Private: The last amount paid by a given user for a listing plan
    #
    # This is used when calculating the amount already paid in the current billing cycle when upgrading to
    # a new plan
    #
    # Returns Billing::Money
    def prepaid_amount_for(user, listing_plan)
      Billing::Money.new \
        user.line_items.for_subscribable(listing_plan).last&.amount_in_cents.to_i
    end

    def subscription_item_quantity_delta(subscription_item)
      old_item = old_item(subscription_item)
      old_item ? subscription_item.quantity - old_item.quantity : subscription_item.quantity
    end

    def free_trial_ending?(subscription_item)
      old_item = old_item(subscription_item)
      return false unless old_item
      old_item.price == Billing::Money.new(0) &&
        subscription_item.price != Billing::Money.new(0)
    end

    def old_item(subscription_item)
      old_subscription.subscription_items.detect do |old_item|
        subscription_item.subscribable == old_item.subscribable
      end
    end
  end
end
