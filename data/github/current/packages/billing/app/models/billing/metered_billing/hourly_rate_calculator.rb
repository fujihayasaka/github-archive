# typed: true
# frozen_string_literal: true

class Billing::MeteredBilling::HourlyRateCalculator
  ASSUMED_DAYS_IN_MONTH = 31

  def initialize(days_in_month: ASSUMED_DAYS_IN_MONTH)
    @days_in_month = days_in_month
    @hours_in_day = 24
  end

  def hourly_unit_cost(cost_per_month:, unit_divisor: 1)
    cost_per_month.to_d / days_in_month / hours_in_day / unit_divisor
  end

  def hourly_rate_for(units_per_month:)
    units_per_month * days_in_month * hours_in_day
  end

  def monthly_rate_for(units_per_hour:)
    units_per_hour.to_d / days_in_month.to_d / hours_in_day.to_d
  end

  private

  attr_reader :days_in_month, :hours_in_day
end
