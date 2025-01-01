# typed: true
# frozen_string_literal: true

module CouponReminder
  extend T::Sig

  # Blast emails to all users who have redeemed a coupon that will
  # expire in two weeks. This runs in the BillingCouponReminderJob job
  # that's enqueued daily by timerd.
  #
  # billing.reminders.two_weeks_coupon_expiring_time.time  - Time it took to sends out the reminders.
  # billing.reminders.two_weeks_coupon_expiring_time.count - Number of users that were notified.
  #
  # billing.biz.reminders.two_weeks_coupon_expiring_time.time  - Time it took to sends out the business reminders.
  # billing.biz.reminders.two_weeks_coupon_expiring_time.count - Number of businesses that were notified.
  sig { void }
  def self.send_two_weeks_coupon_reminders
    GitHub.dogstats.time("billing.reminders.two_weeks_coupon_expiring_time") do
      logins = User.notify_coupon_expiring_in_two_weeks
      GitHub.dogstats.count("billing.reminders.two_weeks_coupon_expiring", logins.size)
    end

    GitHub.dogstats.time("billing.biz.reminders.two_weeks_coupon_expiring_time") do
      businesses = Business.notify_coupon_expiring_in_two_weeks
      GitHub.dogstats.count("billing.biz.reminders.two_weeks_coupon_expiring", businesses.size)
    end
  end

  # Blast emails to all users who have redeemed a coupon that will
  # expire in one week. This runs in the BillingCouponReminderJob job
  # that's enqueued daily by timerd.
  #
  # billing.reminders.one_week_coupon_expiring_time.time  - Time it took to sends out the reminders.
  # billing.reminders.one_week_coupon_expiring_time.count - Number of users that were notified.
  #
  # billing.biz.reminders.one_week_coupon_expiring_time.time  - Time it took to sends out the business reminders.
  # billing.biz.reminders.one_week_coupon_expiring_time.count - Number of businesses that were notified.
  sig { void }
  def self.send_one_week_coupon_reminders
    GitHub.dogstats.time("billing.reminders.one_week_coupon_expiring_time") do
      logins = User.notify_coupon_expiring_in_one_week
      GitHub.dogstats.count("billing.reminders.one_week_coupon_expiring", logins.size)
    end

    GitHub.dogstats.time("billing.biz.reminders.one_week_coupon_expiring_time") do
      businesses = Business.notify_coupon_expiring_in_one_week
      GitHub.dogstats.count("billing.biz.reminders.one_week_coupon_expiring", businesses.size)
    end
  end
end
