# typed: true
# frozen_string_literal: true

require "test_helper"

class GlobalNoticeNext::ExpiredEducationCouponCheckTest < GitHub::TestCase
  fixtures do
    @user = create(:user, :verified, plan: "small")
  end

  context "#should_show_notice?" do
    test "returns true if a user is disabled on a paid plan with expired education coupon" do
      coupon = create(:coupon, group: Coupon::EDUCATION_GROUP_NAMES.first)

      # @user is upgraded to :pro upon coupon redemption
      @user.redeem_coupon(coupon)
      # @user is disabled if they have any private repositories upon coupon
      # expiration
      create(:private_repository, owner: @user)
      @user.reload
      @user.expire_active_coupon

      check = GlobalNoticeNext::ExpiredEducationCouponCheck.new(viewer: @user)
    end

    test "returns false when user is on free plan with expired education coupon" do
      coupon = create(:coupon, group: Coupon::EDUCATION_GROUP_NAMES.first)
      # @user is upgrade to :pro upon coupon redemption
      @user.redeem_coupon(coupon)
      # @user is downgraded to free upon expiration as they have no private repos
      @user.expire_active_coupon

      check = GlobalNoticeNext::ExpiredEducationCouponCheck.new(viewer: @user)

      refute check.should_show_notice?
    end

    test "returns false when user has only free addons" do
      # @user has free marketplace items
      plan_subscription = create(:billing_plan_subscription, user: @user)
      subscription_item = create(:billing_subscription_item, :free, plan_subscription: plan_subscription)

      coupon = create(:coupon, group: Coupon::EDUCATION_GROUP_NAMES.first)
      # @user is upgrade to :pro upon coupon redemption
      @user.redeem_coupon(coupon)
      # and creates a private repo
      create(:private_repository, owner: @user)
      @user.reload
      # and then they are locked when coupon expires
      @user.expire_active_coupon

      # @user manually changes to free plan, but they have addons
      @user.update(plan: :free_with_addons)

      check = GlobalNoticeNext::ExpiredEducationCouponCheck.new(viewer: @user)

      refute check.should_show_notice?
    end

    test "returns false if user does not have an education coupon" do
      check = GlobalNoticeNext::ExpiredEducationCouponCheck.new(viewer: @user)

      refute check.should_show_notice?
    end
  end
end
