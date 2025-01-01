# typed: true
# frozen_string_literal: true

require "test_helper"

class CouponableTest < GitHub::TestCase
  include ActionMailer::TestHelper

  context ".notify_coupon_expiring_in_two_weeks" do
    test "sends an email to users with coupons expiring in two weeks" do
      user = create(:user)
      coupon = create(:coupon, duration: 14)
      user.redeem_coupon(coupon)

      assert_enqueued_emails 1 do
        User.notify_coupon_expiring_in_two_weeks
      end
    end

    test "sends an email to businesses with coupons expiring in two weeks" do
      business_plan_subscription = create \
      :billing_plan_subscription,
      :business_owned
      business = business_plan_subscription.business
      coupon = create(:coupon, duration: 14)
      owner = business.owners.first
      business.redeem_coupon(coupon, actor: owner)

      assert_enqueued_emails 1 do
        Business.notify_coupon_expiring_in_two_weeks
      end
    end
  end

  context ".notify_coupon_expiring_in_one_week" do
    test "sends an email to users with coupons expiring in one week" do
      user = create(:user)
      coupon = create(:coupon, duration: 7)
      user.redeem_coupon(coupon)

      assert_enqueued_emails 1 do
        User.notify_coupon_expiring_in_one_week
      end
    end

    test "sends an email to businesses with coupons expiring in one week" do
      business_plan_subscription = create \
      :billing_plan_subscription,
      :business_owned
      business = business_plan_subscription.business
      coupon = create(:coupon, duration: 7)
      owner = business.owners.first
      business.redeem_coupon(coupon, actor: owner)

      assert_enqueued_emails 1 do
        Business.notify_coupon_expiring_in_one_week
      end
    end
  end

  context "#coupon_redemption" do
    test "can be batch loaded" do
      user_without_coupon = create(:user)

      coupon = create(:coupon)
      user_with_coupon = create(:user)
      coupon_redemption = create(:coupon_redemption, billable_entity: user_with_coupon, coupon: coupon)

      assert_query_count(2) do
        GitHub::PrefillAssociations.prefill_batch_method(
          [user_without_coupon, user_with_coupon],
          :coupon_redemption
        )
      end

      assert_query_count(0) do
        assert_nil user_without_coupon.coupon_redemption
        assert_equal coupon_redemption, user_with_coupon.coupon_redemption
      end
    end
  end

  context "#coupon" do
    test "can be batch loaded" do
      user_without_coupon = create(:user)

      coupon = create(:coupon)
      user_with_coupon = create(:user)
      user_with_coupon.new_coupon_code = coupon.code

      assert_query_count(1) do
        GitHub::PrefillAssociations.prefill_batch_method(
          [user_without_coupon, user_with_coupon],
          :coupon
        )
      end

      assert_query_count(0) do
        assert_equal coupon, user_with_coupon.coupon
        assert_nil user_without_coupon.coupon
      end
    end

    test "raises when batch loading different types of billable entities" do
      user = create(:user)
      business = create(:business)

      assert_raises(Couponable::NonUniqueBillableEntityTypesError) do
        GitHub::PrefillAssociations.prefill_batch_method([user, business], :coupon)
      end
    end
  end
end if GitHub.billing_enabled?
