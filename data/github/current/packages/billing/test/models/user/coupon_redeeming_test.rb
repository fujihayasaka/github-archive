# typed: true
# frozen_string_literal: true

require "test_helper"

if GitHub.billing_enabled?
  class CouponRedeemingTest < GitHub::TestCase
    include GitHub::BillingTest

    setup do
      @user   = create(:user, plan: "small")
      @coupon = create(:coupon, code: "yahoo-devcamp",
                            discount: 0.5,
                            limit: 50)

      assert_nil @user.coupon
      @user.redeem_coupon @coupon.code
      assert_equal @coupon, @user.coupon
    end

    test "validates the coupon" do
      refute @user.redeem_coupon @coupon.code
      assert @user.errors[:coupon].any?
    end

    test "sets billing date" do
      user = create(:user)
      coupon = create(:coupon, discount: "100%", plan: "micro")
      user.redeem_coupon coupon

      assert_equal Date.today, user.billed_on
    end

    test "creates a customer record for the user with the bill cycle day set to the billing date" do
      user = create(:user)
      coupon = create(:coupon, discount: "100%", plan: "micro")

      assert_nil user.customer

      user.redeem_coupon coupon

      assert user.reload.customer
      assert_equal user.billed_on.day, user.customer_bill_cycle_day
    end

    test "expire after they've been redeemed" do
      @user.coupon_redemption.expire!
      user = User.find_by!(id: @user.id)

      assert_nil user.coupon
      assert_equal 0, user.coupons.size
      assert_equal 1, user.expired_coupons.size
    end

    test "can be redeemed after the previously active coupon has expired" do
      coupon2 = create(:coupon, discount: "$12")

      refute @user.redeem_coupon(coupon2)
      assert_equal @coupon, @user.reload.coupon
      assert_equal 1, @user.coupons.size

      @user.coupon_redemption.expire!
      @user.clear_coupon_local_cache

      assert_equal 0, @user.coupons.size
      assert @user.redeem_coupon(coupon2)
      assert_equal coupon2, @user.reload.coupon
      assert_equal 1, @user.coupons.size
    end

    test "sets expiration properly" do
      assert @user.coupon_redemption.expires_at >= GitHub::Billing.now + 29.days
    end

    test "sets amount owed properly" do
      # Coupon is for 50%
      @user.reload
      assert_equal @user.plan.cost * 0.5, @user.payment_amount

      user2 = create(:user, plan: "pro")
      discount = user2.plan.cost - 1
      user2.redeem_coupon create(:coupon, discount: discount)

      assert_equal user2.plan.cost - discount, user2.payment_amount
    end

    test "sets amount owed properly with business_plus rate plans" do
      signup_time = GitHub::Billing.now
      Timecop.freeze(signup_time) do
        user = create(:user, plan: "business_plus", plan_duration: "year")
        user.redeem_coupon create(:coupon, discount: 0.5)

        # User on 'business_plus_252' getting a 50% discount should pay $126
        assert_equal 126, user.reload.payment_amount

        user2  = create(:user, plan: "business_plus", plan_duration: "year")
        # $5/month = $60/year discount
        user2.redeem_coupon create(:coupon, discount: 5)

        # User on 'business_plus_252' getting $60 discount should pay $192
        assert_equal 192, user2.reload.payment_amount
      end
    end

    test "resets billing_attempts for full cost coupons" do
      user = create :user, billing_attempts: 7, plan: "micro"
      user.redeem_coupon create(:coupon, discount: 7)

      assert_equal 0, user.reload.billing_attempts
    end

    test "does not reset billing_attempts for partial coupons" do
      user = create :user, billing_attempts: 7, plan: "micro"
      user.redeem_coupon create(:coupon, discount: 5)

      assert_equal 7, user.reload.billing_attempts
    end

    test "decrements the coupon's redemption limit" do
      assert_equal 49, @coupon.reload.limit
    end

    test "associates the discount with the user and coupon" do
      assert_equal [@user], @coupon.users
    end

    test "upgrades their plan if the coupon is for a free trial" do
      coupon = create(:coupon, plan: "medium", discount: "100%")
      user   = create(:user, plan: "micro")

      user.redeem_coupon(coupon)

      user.reload
      assert_equal coupon, user.coupon
      assert_equal coupon.plan, user.plan
      assert_kind_of Date, user.billed_on
    end

    test "upgrades their plan only to Pro but their coupon would otherwise bump them to a higher plan" do
      coupon = create(:coupon, discount: 20)
      user   = create(:user, plan: "pro")

      user.redeem_coupon(coupon)

      user.reload
      assert_equal coupon, user.coupon
      assert_equal user.plan, GitHub::Plan.pro
      assert_kind_of Date, user.billed_on
    end

    test "can't give negative discounts" do
      user = create(:user, plan: "small")
      coupon = create(:coupon, discount: 100)

      user.redeem_coupon(coupon)
      assert_equal 0, user.payment_amount
    end

    test "User#free_trial?" do
      plan = GitHub::Plan.pro
      # Coupon that explicitly covers 100% of a plan
      user = create(:user, plan: plan)
      coupon_1 = create(:coupon, plan: plan, discount: "1.0")
      assert user.redeem_coupon coupon_1
      assert user.free_trial?

      # Coupon that covers the full cost of a plan is a free trial
      user = create(:user, plan: plan)
      coupon_2 = create(:coupon, discount: "$#{plan.cost}")
      assert user.redeem_coupon coupon_2
      assert user.free_trial?

      # Coupon that covers half the cost of a plan is not a free trial
      user = create(:user, plan: plan)
      coupon_3 = create(:coupon, discount: "$#{plan.cost - 1}")
      assert user.redeem_coupon coupon_3
      refute user.free_trial?
    end

    test "User#free_trial? with plan-only coupon is false if user has data packs" do
      user = create(:user, plan: "small")
      Asset::Status.create!(owner: user, asset_packs: 1)

      user.redeem_coupon create(:coupon, plan: "small", discount: "1.0")
      refute user.free_trial?, "Coupon should not cover cost of data packs"
    end

    test "User#free_trial? with coupon is true if it covers data packs" do
      user = create :user, plan: "free"
      Asset::Status.create!(owner: user, asset_packs: 2)

      user.redeem_coupon create(:coupon, discount: "$22")
      assert user.free_trial?, "Coupon should cover full cost of data packs"
    end

    test "User#free_trial? with coupon is false if doesn't cover data packs" do
      plan = GitHub::Plan.pro
      user = create :user, plan: plan
      Asset::Status.create!(owner: user, asset_packs: 3)

      discount = Asset::Status.data_pack_unit_price * 3 + Billing::Money.new(plan.cost * 100)
      user.redeem_coupon create(:coupon, discount: "$#{discount.dollars - 1}")
      refute user.free_trial?, "Coupon should not cover cost of data packs"
    end

    if GitHub.spamminess_check_enabled?
      test "can't be applied to a spammy user" do
        user = create(:user, spammy: true)
        coupon = create(:coupon, discount: "$7")
        redemption = user.redeem_coupon(coupon)

        assert_equal false, redemption
        assert_nil user.coupon
      end
    end

    context "#best_plan_for_coupon with $ discount" do
      test "gives the highest plan that would still be free for the user" do
        user = create(:user, plan: "micro")
        coupon = create(:coupon, discount: 15)
        user.coupon = coupon
        assert_equal "pro", user.best_plan_for_coupon.name
      end

      test "considers data packs when calculating largest plan that would be free" do
        user = create(:user, plan: "micro")
        create(:asset_status, owner: user, asset_packs: 2)

        coupon = create(:coupon, discount: 25)
        user.coupon = coupon

        assert_equal "pro", user.best_plan_for_coupon.name
      end

      test "coupon for a user with new pricing returns the pro plan" do
        user = create(:user, plan: "free")
        coupon = create(:coupon, discount: 25)
        user.coupon = coupon
        assert_equal "pro", user.best_plan_for_coupon.name
      end

      test "small coupon for user with addons should return the free_with_addons plan" do
        user = create(:user, plan: "free_with_addons")
        create(:asset_status, owner: user, asset_packs: 1)

        coupon = create(:coupon, discount: 7)
        user.coupon = coupon

        assert_equal "free_with_addons", user.best_plan_for_coupon.name
      end

      test "small coupon for a user with new pricing returns the free plan" do
        plan = GitHub::Plan.pro
        user = create(:user, plan: "free")
        coupon = create(:coupon, discount: plan.cost - 1)
        user.coupon = coupon
        assert_equal "free", user.best_plan_for_coupon.name
      end

      test "small coupon for an org returns the free plan" do
        org = create(:organization, plan: "free")
        coupon = create(:coupon, discount: org.plan.cost - 1)
        org.coupon = coupon
        assert_equal "free", org.best_plan_for_coupon.name
      end
    end

    context "#best_plan_for_coupon using a %-off coupon with no associated plan (legacy coupons)" do
      test "for a user on a paid plan, gives the current plan" do
        user = create(:user, plan: "micro")
        coupon = create(:coupon, discount: 0.25, plan: nil)
        user.coupon = coupon
        assert_equal "pro", user.best_plan_for_coupon.name.to_s
      end

      test "for a user on the free plan, gives the free plan" do
        user = create(:user, plan: "free")
        coupon = create(:coupon, discount: 0.25, plan: nil)
        user.coupon = coupon
        assert_equal "free", user.best_plan_for_coupon.name.to_s
      end

      test "for an org on the free plan, gives the free plan" do
        org = create(:organization, plan: "free")
        coupon = create(:coupon, discount: 0.25, plan: nil)
        org.coupon = coupon
        assert_equal "free", org.best_plan_for_coupon.name.to_s
      end

      test "for an org on the free plan and fully paid coupon, gives the team plan" do
        org = create(:organization, plan: "free")
        coupon = create(:coupon, discount: 1.00, plan: nil)
        org.coupon = coupon
        assert_equal GitHub::Plan.business.to_s, org.best_plan_for_coupon.name.to_s
      end

      test "for an org on the free_with_addons plan and fully paid coupon, gives the team plan" do
        org = create(:organization, plan: "free_with_addons")
        coupon = create(:coupon, discount: 1.00, plan: nil)
        org.coupon = coupon
        assert_equal GitHub::Plan.business.to_s, org.best_plan_for_coupon.name.to_s
      end

      test "for an org on a paid plan, gives the current plan" do
        org = create(:organization, plan: "bronze")
        coupon = create(:coupon, discount: 0.25, plan: nil)
        org.coupon = coupon
        assert_equal "bronze", org.best_plan_for_coupon.name.to_s
      end

    end

    context "#best_plan_for_coupon using a %-off plan-specific coupon" do
      test "for a user on a free plan, gives the coupon's plan" do
        user = create(:user, plan: "free")
        coupon = create(:coupon, discount: 0.25, plan: "micro")
        user.coupon = coupon
        assert_equal "micro", user.best_plan_for_coupon.name.to_s
      end

      test "for a user on a paid plan, gives the coupon's plan" do
        user = create(:user, plan: "micro")
        coupon = create(:coupon, discount: 0.25, plan: "small")
        user.coupon = coupon
        assert_equal "small", user.best_plan_for_coupon.name.to_s
      end

      test "for an org on the free plan, gives the coupon's plan" do
        org = create(:organization, plan: "free")
        coupon = create(:coupon, discount: 0.25, plan: "bronze")
        org.coupon = coupon
        assert_equal "bronze", org.best_plan_for_coupon.name.to_s
      end

      test "for an org on a paid plan, gives the coupon's plan" do
        org = create(:organization, plan: "silver")
        coupon = create(:coupon, discount: 0.25, plan: "bronze")
        org.coupon = coupon
        assert_equal "bronze", org.best_plan_for_coupon.name.to_s
      end
    end

    context "#best_plan_for_coupon using a $-off plan-specific coupon" do
      test "for an organization on the free plan, gives the coupon's plan" do
        org = create(:organization, plan: "free")
        coupon = create(:coupon, discount: 420, plan: "business_plus")
        org.coupon = coupon
        assert_equal "business_plus", org.best_plan_for_coupon.name.to_s
      end

      test "for an organization on a team's plan, gives the coupon's plan" do
        org = create(:organization, plan: "business")
        coupon = create(:coupon, discount: 420, plan: "business_plus")
        org.coupon = coupon
        assert_equal "business_plus", org.best_plan_for_coupon.name.to_s
      end
    end

    test "for a trial coupon, gives the coupon's plan" do
      user = create(:user, plan: "micro")
      coupon = create(:coupon, discount: 1, plan: "small")
      user.coupon = coupon
      assert_equal "small", user.best_plan_for_coupon.name.to_s
    end
  end
end
