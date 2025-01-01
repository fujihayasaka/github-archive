# typed: true
# frozen_string_literal: true

require "test_helper"

if GitHub.billing_enabled?
  class CouponExpirationTest < GitHub::TestCase
    include GitHub::BillingTest

    fixtures do
      @coupon = create(:coupon, discount: "$12")
      @user = create(:user)
    end

    setup do
      @user.redeem_coupon @coupon
    end

    test "aren't returned until they're ready" do
      Timecop.freeze(GitHub::Billing.now.beginning_of_day + 11.hours) do
        assert_empty CouponRedemption.expiring_in_two_weeks.map(&:billable_entity)
        assert_empty CouponRedemption.expiring_in_one_week.map(&:billable_entity)
        assert_empty CouponRedemption.expiring_now.map(&:billable_entity)
        assert_empty CouponRedemption.expiring_before(GitHub::Billing.now - 1.day).map(&:billable_entity)
      end
    end

    test "this billing cycle" do
      Timecop.freeze(GitHub::Billing.now.beginning_of_day + 11.hours) do
        user = create(:user, billed_on: GitHub::Billing.today + 3.weeks)
        coupon = create(:coupon, discount: "12", duration: 4 * 7)
        user.redeem_coupon(coupon)
        refute user.coupon_redemption.expires_this_billing_cycle?

        user = create(:user, billed_on: GitHub::Billing.today + 3.weeks)
        coupon = create(:coupon, discount: "12", duration: 2 * 7)
        user.redeem_coupon(coupon)
        assert user.coupon_redemption.expires_this_billing_cycle?

        user = create(:user)
        coupon = create(:coupon, discount: "12", duration: 2 * 7)
        user.redeem_coupon(coupon)
        user.update(billed_on: nil) # this can happen when a user cancels a plan and then starts a new one
        refute user.coupon_redemption.expires_this_billing_cycle?
      end
    end

    test "soon" do
      Timecop.freeze(GitHub::Billing.now.beginning_of_day + 11.hours) do
        @user.coupon_redemption.update_attribute :expires_at, GitHub::Billing.now.at_midnight + 15.days - 1.hour
        assert_equal [@user], CouponRedemption.expiring_in_two_weeks.map(&:billable_entity)
      end
    end

    test "already expired" do
      Timecop.freeze(GitHub::Billing.now.beginning_of_day + 11.hours) do
        @user.coupon_redemption.update(
          expires_at: GitHub::Billing.now + 3.weeks,
          expired: true,
        )
        assert_empty CouponRedemption.expiring_in_two_weeks.map(&:billable_entity)
      end
    end

    test "today" do
      Timecop.freeze(GitHub::Billing.now.beginning_of_day + 11.hours) do
        @user.coupon_redemption.update_attribute :expires_at, GitHub::Billing.now - 1.hour
        assert_equal [@user], CouponRedemption.expiring_now.map(&:billable_entity)

        @user.coupon_redemption.expire!
        assert_empty CouponRedemption.expiring_now.map(&:billable_entity)
      end
    end

    test "at time" do
      Timecop.freeze(GitHub::Billing.now.beginning_of_day + 11.hours) do
        @user.coupon_redemption.update_attribute :expires_at, GitHub::Billing.now + 1.day
        assert_equal [@user], CouponRedemption.expiring_before(GitHub::Billing.now + 2.days).map(&:billable_entity)
      end
    end

    test "are stale until after end of day" do
      Timecop.freeze(GitHub::Billing.now.beginning_of_day + 11.hours) do
        @user.coupon_redemption.update_attribute :expires_at, GitHub::Billing.now - 12.hours
        assert @user.coupon_redemption.stale?
      end
    end

    test "are not stale for the full expiration day" do
      Timecop.freeze(GitHub::Billing.now.beginning_of_day + 11.hours) do
        @user.coupon_redemption.update_attribute :expires_at, GitHub::Billing.now - 1.hour
        refute @user.coupon_redemption.stale?
      end
    end
  end
end
