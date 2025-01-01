# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class BillingCouponReminderJob < BillingJob
  schedule interval: 24.hours, condition: -> { !GitHub.enterprise? }

  exempt_from_tenant_context_requirement

  def perform
    with_write do
      CouponReminder.send_two_weeks_coupon_reminders
      CouponReminder.send_one_week_coupon_reminders
    end
  end
end
