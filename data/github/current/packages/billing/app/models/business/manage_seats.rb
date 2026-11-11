# typed: true
# frozen_string_literal: true

class Business::ManageSeats
  include GitHub::Memoizer

  attr_reader :business, :new_seats, :baseline_seats

  EMDASH = "\u{2014}"
  MAX_TRIAL_SEATS = 50

  def initialize(business:, new_seats:, baseline_seats: nil)
    @business = business
    @new_seats = new_seats || @business.seats
    @baseline_seats = baseline_seats
  end

  memoize def payment_term_label
    if monthly_plan?
      is_in_trial? ? "Estimated monthly payment" : "Monthly payment"
    else
      is_in_trial? ? "Estimated yearly payment" : "Yearly payment"
    end
  end

  memoize def seat_cost_label_short
    if monthly_plan?
      "#{seat_change.unit_price.format}/user per month"
    else
      "#{seat_change.unit_price.format}/user per year"
    end
  end

  memoize def seat_cost_label
    if monthly_plan?
      "Each seat costs #{seat_change.unit_price.format} per month"
    else
      "Each seat costs #{seat_change.unit_price.format} per year"
    end
  end

  memoize def show_payment_increase?
    return false if is_in_trial?
    valid_seats > current_seats
  end

  memoize def show_payment_decrease?
    return false if is_in_trial?
    valid_seats < current_seats
  end

  memoize def current_price
    seat_change_current.current_price
  end

  memoize def price_update
    seat_change.current_price
  end

  memoize def payment_decrease
    return unless show_payment_decrease?
    "#{(current_price - price_update).format}"
  end

  memoize def payment_increase
    return unless show_payment_increase?
    "#{(price_update - current_price).format}"
  end

  memoize def seats
    @new_seats || current_seats
  end

  memoize def payment_label
    if valid_seats == current_seats
      current_payment
    else
      price_update.format
    end
  end

  memoize def new_payment
    seat_change.renewal_price.format
  end

  memoize def current_payment
    current_price.format
  end

  memoize def payment_due
    if is_in_trial? || valid_seats <= current_seats
      EMDASH
    else
      seat_change.payment_amount.format
    end
  end

  memoize def payment_due_notice
    if is_in_trial?
      ""
    elsif !is_in_trial? && valid_seats <= current_seats
      "Your changes will take effect on #{next_billing_date}"
    elsif valid_seats == current_seats
      "Your next payment of #{current_payment} will be due on #{next_billing_date}"
    else
      "Your next payment of #{new_payment} will be due on #{next_billing_date}"
    end
  end

  memoize def sales_tax_notice
    if @business.display_sales_tax_on_checkout? && valid_seats > current_seats
      "Sales tax will be added to your invoice"
    else
      " "
    end
  end

  memoize def min_seats
    [current_seats - max_seats_delta, [total_consumed_licenses, 1].max].max
  end

  memoize def max_seats
    return MAX_TRIAL_SEATS if is_in_trial?
    current_seats + max_seats_delta
  end

  memoize def current_seats
    return total_consumed_licenses if !!business.metered_plan?

    # Use baseline seats if provided (for pending cycle changes), otherwise use business seats
    @baseline_seats || @business.seats
  end

  memoize def next_billing_date
    if is_in_trial?
      business.trial_expires_at.to_date.strftime("%B %-e, %Y")
    else
      billed_on.strftime("%B %-e, %Y")
    end
  end

  memoize def billed_on
    business.billed_on
  end

  memoize def monthly_plan?
    plan_duration == User::BillingDependency::MONTHLY_PLAN
  end

  memoize def valid_seats
    [[@new_seats, min_seats].max, max_seats].min
  end

  memoize def seat_change
    Billing::PlanChange::SeatChange.new(business, seats: valid_seats, plan_and_seat_cost_only: true)
  end

  memoize def is_in_trial?
    business.trial?
  end

  memoize def has_unlimited_seats?
    !!business.has_unlimited_seats?
  end

  memoize def can_manage_seats?
    !!business.can_manage_seats?
  end

  private

  memoize def plan_duration
    business.plan_duration
  end

  memoize def seat_change_current
    Billing::PlanChange::SeatChange.new(business, seats: current_seats, plan_and_seat_cost_only: true)
  end

  memoize def max_seats_delta
    ::Billing::ChangeSubscription::MAX_SEAT_DELTA
  end

  memoize def seats_delta
    @new_seats - business.seats
  end

  memoize def total_consumed_licenses
    business.total_consumed_licenses
  end
end
