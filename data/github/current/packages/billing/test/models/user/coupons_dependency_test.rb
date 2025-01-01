# typed: true
# frozen_string_literal: true

require "test_helper"

class UserCouponsDependencyTest < GitHub::TestCase
  context "#coupon_redemption" do
    test "can be batch loaded for multiple users efficiently" do
      user_without_coupon1, user_without_coupon2 = create_pair(:user)
      coupon1, coupon2 = create_pair(:coupon)
      coupon3 = create(:coupon, limit: 2)

      user_with_new_coupon1, user_with_new_coupon2 = create_pair(:user)
      user_with_new_coupon1.new_coupon_code = coupon1.code
      user_with_new_coupon2.new_coupon_code = coupon2.code

      user_with_coupon = create(:user)
      coupon_redemption = create(:coupon_redemption, billable_entity: user_with_coupon, coupon: coupon3)

      expired_coupon_redemption = create(:coupon_redemption, :expired)
      user_with_expired_coupon = expired_coupon_redemption.billable_entity

      # A user whose latest redemption uses an older coupon than their earlier, expired redemption:
      prev_coupon_redemption = create(:coupon_redemption, :expired, coupon: coupon3)
      user_with_multiple_redemptions = prev_coupon_redemption.billable_entity
      latest_coupon_redemption = create(:coupon_redemption, billable_entity: user_with_multiple_redemptions, coupon: coupon1)

      users = [user_without_coupon1, user_with_new_coupon1, user_with_coupon, user_with_new_coupon2,
        user_without_coupon2, user_with_expired_coupon, user_with_multiple_redemptions]

      assert_query_count(2) do
        GitHub::PrefillAssociations.prefill_batch_method(users, :coupon_redemption)
      end

      assert_query_count(0) do
        assert_nil user_with_new_coupon1.coupon_redemption
        assert_nil user_with_new_coupon2.coupon_redemption
        assert_nil user_without_coupon1.coupon_redemption
        assert_nil user_without_coupon2.coupon_redemption
        assert_equal coupon_redemption, user_with_coupon.coupon_redemption
        assert_nil user_with_expired_coupon.coupon_redemption
        assert_equal latest_coupon_redemption, user_with_multiple_redemptions.coupon_redemption
      end
    end
  end

  context "#coupon" do
    test "can be batch loaded for multiple users efficiently" do
      user_without_coupon1, user_without_coupon2 = create_pair(:user)
      coupon1, coupon2 = create_pair(:coupon)
      coupon3 = create(:coupon, limit: 2)

      user_with_new_coupon1 = create(:user)
      user_with_new_coupon1.new_coupon_code = coupon1.code
      user_with_new_coupon2 = create(:user)
      user_with_new_coupon2.new_coupon_code = coupon2.code

      user_with_coupon = create(:user)
      coupon_redemption = create(:coupon_redemption, billable_entity: user_with_coupon, coupon: coupon3)

      expired_coupon_redemption = create(:coupon_redemption, :expired)
      user_with_expired_coupon = expired_coupon_redemption.billable_entity

      # A user whose latest redemption uses an older coupon than their earlier, expired redemption:
      prev_coupon_redemption = create(:coupon_redemption, :expired, coupon: coupon3)
      user_with_multiple_redemptions = prev_coupon_redemption.billable_entity
      latest_coupon_redemption = create(:coupon_redemption, billable_entity: user_with_multiple_redemptions, coupon: coupon1)

      users = [user_without_coupon1, user_with_new_coupon1, user_with_coupon, user_with_new_coupon2,
        user_without_coupon2, user_with_expired_coupon, user_with_multiple_redemptions]

      assert_query_count(1) do
        GitHub::PrefillAssociations.prefill_batch_method(users, :coupon)
      end

      assert_query_count(0) do
        assert_equal coupon1, user_with_new_coupon1.coupon
        assert_equal coupon2, user_with_new_coupon2.coupon
        assert_nil user_without_coupon1.coupon
        assert_nil user_without_coupon2.coupon
        assert_equal coupon_redemption.coupon, user_with_coupon.coupon
        assert_nil user_with_expired_coupon.coupon
        assert_equal latest_coupon_redemption.coupon, user_with_multiple_redemptions.coupon
      end
    end
  end
end
