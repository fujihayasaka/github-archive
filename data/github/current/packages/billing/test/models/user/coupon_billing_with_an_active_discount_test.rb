# typed: true
# frozen_string_literal: true

require "test_helper"

if GitHub.billing_enabled?
  class CouponBillingWithAnActiveDiscountTest < GitHub::TestCase
    include GitHub::BillingTest

    fixtures do
      @coupon = create(:coupon, discount: "$12")
      @user = create(:user)
    end

    setup do
      @user.redeem_coupon @coupon
    end

    test "doesn't expire the coupon prematurely" do
      Timecop.freeze(GitHub::Billing.now.beginning_of_day + 30.minutes) do
        @user.recurring_charge
        refute @user.coupon_redemption.nil?
      end
    end

    test "can have a stale coupon" do
      Timecop.freeze(GitHub::Billing.now.beginning_of_day + 30.minutes) do
        @user.coupon_redemption.update_attribute :expires_at, GitHub::Billing.now - 1.hour
        assert @user.coupon_redemption.stale?
      end
    end
  end
end
