# typed: true
# frozen_string_literal: true

require "test_helper"

if GitHub.billing_enabled?
  class CouponValidationTest < GitHub::TestCase
    include GitHub::BillingTest

    fixtures do
      @user   = create :user, plan: "micro"
      @coupon = create(:coupon, code: "50off", discount: 0.5, limit: 50)
    end

    test "can't be redeemed by users on strange billing_types" do
      @user.update_attribute(:billing_type, "gift")
      @user.coupon = @coupon
      refute @user.validate_coupon!
      assert @user.errors[:coupon].any?
    end

    test "is invalid when user is OFAC sanctioned" do
      user = create :user, :fully_trade_restricted, plan: "micro"

      user.coupon = @coupon
      refute user.validate_coupon!
      assert_includes user.errors.full_messages.to_sentence, TradeControls::Notices.notice_as_plaintext(:user_account_restricted)
    end

    test "can't be redeemed by users who are OFAC sanctioned" do
      user = create :user, :fully_trade_restricted, plan: "micro"
      staff = create :staff_admin_user
      coupon = create :coupon, code: "10-off", discount: 0.5, staff_actor_only: true

      refute user.redeem_coupon("10-off", actor: staff)
      assert_nil user.coupon
      assert_includes user.errors.full_messages.to_sentence, TradeControls::Notices.notice_as_plaintext(:user_account_restricted)
    end

    test "is invalid for organization owned by business" do
      org = create :organization, business: create(:business, :with_self_serve_payment)
      refute_nil org.business
      assert_predicate org, :delegate_billing_to_business?

      org.coupon = @coupon
      refute org.validate_coupon!
      assert_match /can't be redeemed against enterprise account organizations/, org.errors.full_messages.to_sentence
    end

    test "can't be redeemed by organization owned by business" do
      org = create :organization, business: create(:business, :with_self_serve_payment)
      staff = create :staff_admin_user
      coupon = create :coupon, code: "10-off", discount: 0.5, staff_actor_only: true

      refute org.redeem_coupon("10-off", actor: staff)
      assert_nil org.coupon
      assert_match /can't be redeemed against enterprise account organizations/, org.errors.full_messages.to_sentence
    end

    test "staff_actor_only coupons can only be redeemed by staff" do
      user = create :user, plan: "micro"
      staff = create :staff_admin_user
      coupon = create :coupon, code: "10-off", discount: 0.5, staff_actor_only: true

      refute user.redeem_coupon("10-off"),
        "Redemption should fail for a non-staff actor"
      assert_match /can't be redeemed/, user.errors.full_messages.to_sentence

      refute user.redeem_coupon("10-off", actor: nil),
        "Redemption should fail for a nil actor"
      assert_match /can't be redeemed/, user.errors.full_messages.to_sentence

      user.errors.clear

      assert user.redeem_coupon("10-off", actor: staff),
        "Redemption should succeed for a staff actor"
      assert user.errors.none?
    end

    test "can be redeemed by users on per seat" do
      coupon = create(:coupon, discount: 5)
      user = create :user, plan: "business"
      user.coupon = coupon
      assert user.validate_coupon!
    end

    test "can be redeemed by an org if the coupon plan is an upgrade from the org's plan" do
      coupon = create(:coupon, discount: 420, plan: "business_plus")
      org = create :organization, plan: "business"
      org.coupon = coupon
      assert org.validate_coupon!
    end

    test "can be redeemed by an org on a free plan" do
      coupon = create(:coupon, discount: 420, plan: "business_plus")
      org = create :organization, plan: "free"
      org.coupon = coupon
      assert org.validate_coupon!
    end

    test "can't be redeemed for the wrong plan" do
      coupon = create(:coupon, discount: 5, plan: "bronze")
      org = create :organization, plan: "business"
      org.coupon = coupon
      refute org.validate_coupon!
    end

    test "can expire before they're redeemed" do
      coupon = create(:coupon, expires_at: GitHub::Billing.now - 2.days, discount: "$12")
      @user.coupon = coupon
      refute @user.validate_coupon!
      assert @user.errors[:coupon].any?
    end

    test "is required for some plans" do
      user = User.create(plan: "custom300")
      assert user.errors[:coupon].any?

      user = User.create(plan: "custom300")
      user.coupon = @coupon
      assert user.errors[:coupon].any?

      user = User.new(plan: "custom300")
      user.coupon = create(:coupon, discount: 0, plan: "custom300")
      assert user.validate_coupon!
    end

    test "is required for some plans (but not for staff)" do
      user = create(:staff_admin_user)
      user.plan = "custom300"
      refute user.errors[:coupon].any?
    end

    test "can't be stacked" do
      @user.redeem_coupon(@coupon)
      coupon2 = create(:coupon, discount: "$12")
      refute @user.validate_coupon(coupon2.code)
      assert @user.errors[:coupon].any?
    end

    test "can't be redeemed with a made-up code" do
      refute @user.validate_coupon("defunktion")
      assert @user.errors[:coupon].any?
    end

    test "invalid if the coupon has reached its limit" do
      coupon = create(:coupon, discount: "50%", limit: 1)
      assert create(:user).redeem_coupon(coupon)
      refute @user.validate_coupon(coupon.code)
      assert @user.errors[:coupon].any?
    end

    test "invalid if coupon has a plan that the target doesn't support" do
      coupon = create(:coupon, plan: "business", discount: "50%")
      refute @user.validate_coupon(coupon.code)
      assert @user.errors[:coupon].any?
    end

    test "can't be redeemed by the same user again" do
      @user.redeem_coupon(@coupon)
      @user.expire_active_coupon
      @user.reload
      refute @user.validate_coupon(@coupon.code)
      assert @user.errors[:coupon].any?
    end
  end
end
