# frozen_string_literal: true

module BillingTimeExtensions
  def in_billing_timezone
    in_time_zone(GitHub::Billing.timezone)
  end

  def to_billing_date
    in_billing_timezone.to_date
  end
end

Time.include BillingTimeExtensions
DateTime.include BillingTimeExtensions
ActiveSupport::TimeWithZone.include BillingTimeExtensions
