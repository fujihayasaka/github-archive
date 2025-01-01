# typed: true
# frozen_string_literal: true

module Codespaces
  class StorageBillingMessageTrackedUsage < BillingMessageTrackedUsage
    SECONDS_IN_AN_HOUR = 3600

    attr_reader :size_in_kb
    def post_intialize(usage_data:, codespace_guid:, usage_type:)
      @size_in_kb = usage_data["sizeInKb"]
    end

    memoize def size_in_bytes
      size_in_kb * Numeric::KILOBYTE
    end

    memoize def computed_usage_in_gb_month
      calculator = ::Billing::MeteredBilling::HourlyRateCalculator.new

      gb_hours = (size_in_bytes.to_f / Numeric::GIGABYTE) * (billable_duration_in_seconds.to_d / SECONDS_IN_AN_HOUR)
      calculator.monthly_rate_for(units_per_hour: gb_hours).to_f
    end
  end
end
