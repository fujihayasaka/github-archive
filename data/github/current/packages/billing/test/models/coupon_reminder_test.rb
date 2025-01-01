# typed: true
# frozen_string_literal: true

require "test_helper"

class CouponReminderTest < GitHub::TestCase
  include DogstatsTestHelpers

  test "sends an email to users with coupons expiring in two weeks" do
    user = create(:user)
    coupon = create(:coupon, duration: 14)
    user.redeem_coupon(coupon)

    CouponReminder.send_two_weeks_coupon_reminders

    assert_dogstats_count_value 1, "billing.reminders.two_weeks_coupon_expiring"
    assert_dogstats_count_value 0, "billing.biz.reminders.two_weeks_coupon_expiring"
  end

  test "sends an email to businesses with coupons expiring in two weeks" do
    business_plan_subscription = create \
    :billing_plan_subscription,
    :business_owned
    business = business_plan_subscription.business
    coupon = create(:coupon, duration: 14)
    owner = business.owners.first
    business.redeem_coupon(coupon, actor: owner)

    CouponReminder.send_two_weeks_coupon_reminders

    assert_dogstats_count_value 0, "billing.reminders.two_weeks_coupon_expiring"
    assert_dogstats_count_value 1, "billing.biz.reminders.two_weeks_coupon_expiring"
  end

  test "sends an email to users with coupons expiring in one week" do
    user = create(:user)
    coupon = create(:coupon, duration: 7)
    user.redeem_coupon(coupon)

    CouponReminder.send_one_week_coupon_reminders

    assert_dogstats_count_value 1, "billing.reminders.one_week_coupon_expiring"
    assert_dogstats_count_value 0, "billing.biz.reminders.one_week_coupon_expiring"
  end

  test "sends an email to businesses with coupons expiring in one week" do
    business_plan_subscription = create \
    :billing_plan_subscription,
    :business_owned
    business = business_plan_subscription.business
    coupon = create(:coupon, duration: 7)
    owner = business.owners.first
    business.redeem_coupon(coupon, actor: owner)

    CouponReminder.send_one_week_coupon_reminders

    assert_dogstats_count_value 0, "billing.reminders.one_week_coupon_expiring"
    assert_dogstats_count_value 1, "billing.biz.reminders.one_week_coupon_expiring"
  end
end if GitHub.billing_enabled?
