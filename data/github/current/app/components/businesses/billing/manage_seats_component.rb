# typed: true
# frozen_string_literal: true
class Businesses::Billing::ManageSeatsComponent < ApplicationComponent
  attr_reader :business, :manage_seats, :available_enterprise_licenses, :billing_term_ends_on

  delegate :payment_term_label,
    :current_seats,
    :current_payment,
    :seats,
    :payment_label,
    :show_payment_increase?,
    :show_payment_decrease?,
    :payment_due,
    :payment_due_notice,
    :payment_increase,
    :payment_decrease,
    :seat_cost_label,
    :seat_cost_label_short,
    :next_billing_date,
    :monthly_plan?,
    :min_seats,
    :max_seats,
    :is_in_trial?,
    :has_unlimited_seats?,
    :can_manage_seats?,
    to: :manage_seats

  def initialize(business:, new_seats: nil, available_enterprise_licenses:, billing_term_ends_on:)
    @business = business
    @new_seats = new_seats
    @available_enterprise_licenses = available_enterprise_licenses
    @billing_term_ends_on = billing_term_ends_on
    @manage_seats = Business::ManageSeats.new(business: business, new_seats: new_seats)
  end

  def render?
    business.eligible_for_self_serve_payment?
  end

  memoize def enterprise_licenses_label
    if is_in_trial?
      formatted_licenses = "#{number_with_delimiter(available_enterprise_licenses)} #{"trial license".pluralize(available_enterprise_licenses)}"
      "#{formatted_licenses} #{"is".pluralize(available_enterprise_licenses)} available."
    elsif has_unlimited_seats?
      "Unlimited seats are available"
    else
      formatted_licenses = "#{number_with_delimiter(available_enterprise_licenses)} #{"license".pluralize(available_enterprise_licenses)}"
      "#{formatted_licenses} #{"is".pluralize(available_enterprise_licenses)} available, valid until #{billing_term_ends_on} (includes support and updates)."
    end
  end

  memoize def min_error_message
    "You need at least #{pluralize(min_seats, "seat")}"
  end

  memoize def max_error_message
    if is_in_trial?
      "You may have a maximum of #{Business::ManageSeats::MAX_TRIAL_SEATS} seats during your trial."
    else
      "You can only add or remove up to #{::Billing::ChangeSubscription::MAX_SEAT_DELTA} seats at a time"
    end
  end
end
