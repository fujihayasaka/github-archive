# typed: true
# frozen_string_literal: true

require "test_helper"

class Billing::PlanChange::DataPackChangeTest < GitHub::BillingTestCase

  fixtures do
    # Braintree doesn't include today in its proration calculation, so add
    # a day to get an even prorated amount for simpler test expectations.
    @user = create :user, plan: "large", billed_on: GitHub::Billing.today + 1.month + 1.day
  end

  context "#min_packs_to_cover_usage" do
    test "on free tier" do
      asset_status = create(:asset_status, storage: 0.1, owner: @user, asset_packs: 1)
      change = Billing::PlanChange::DataPackChange.new(@user, total_packs: 1)
      assert_equal 0, change.min_packs_to_cover_usage
      assert_equal [1, 0], change.downgrade_options
    end

    test "on paid tier not using storage" do
      asset_status = create(:asset_status, storage: 0.1, owner: @user, asset_packs: 3)
      change = Billing::PlanChange::DataPackChange.new(@user, total_packs: 3)
      assert_equal 0, change.min_packs_to_cover_usage
      assert_equal [3, 2, 1, 0], change.downgrade_options
    end

    test "on paid tier using almost 2 packs" do
      asset_status = create(:asset_status, storage: 99.0, owner: @user, asset_packs: 3)
      change = Billing::PlanChange::DataPackChange.new(@user, total_packs: 3)
      assert_equal 2, change.min_packs_to_cover_usage
      assert_equal [3, 2], change.downgrade_options
    end

    test "on paid tier using exactly 2 packs" do
      asset_status = create(:asset_status, storage: 100.0, owner: @user, asset_packs: 3)
      change = Billing::PlanChange::DataPackChange.new(@user, total_packs: 3)
      assert_equal 2, change.min_packs_to_cover_usage
      assert_equal [3, 2], change.downgrade_options
    end

    test "on paid tier using 3 packs" do
      asset_status = create(:asset_status, storage: 100.1, owner: @user, asset_packs: 3)
      change = Billing::PlanChange::DataPackChange.new(@user, total_packs: 3)
      assert_equal 3, change.min_packs_to_cover_usage
      assert_equal [3], change.downgrade_options
    end
  end

  context "#undiscounted_price" do
    test "works at month edge boundaries" do
      Timecop.freeze(GitHub::Billing.timezone.local(2015, 5, 31)) do
        user = create :user, plan: "large", billed_on: Date.new(2015, 7, 1)
        user.redeem_coupon create(:coupon, discount: 5)

        change = Billing::PlanChange::DataPackChange.new(user, total_packs: 1)
        assert_equal Billing::Money.new(5_00), change.undiscounted_price
      end
    end

    test "calculates prorated amount" do
      Timecop.freeze(GitHub::Billing.timezone.local(2015, 5, 10)) do
        user = create :user, plan: "large", billed_on: Date.new(2015, 5, 21)
        change = Billing::PlanChange::DataPackChange.new(user, total_packs: 1)
        assert_equal Billing::Money.new((10 / 30.0 * 5_00).to_i), change.undiscounted_price
      end
    end
  end

  context "#total_price" do
    test "can take balance into account" do
      FakeZuora.mock
      user = create(:user, plan: GitHub::Plan.free)
      plan_subscription = create(:billing_plan_subscription, :zuora, user: user, balance_in_cents: -1_00)
      seat_change = Billing::PlanChange::DataPackChange.new(plan_subscription.user, total_packs: 1)

      assert_equal Billing::Money.new(4_00), seat_change.total_price
    end

    test "can take balance into account and never negative" do
      FakeZuora.mock
      user = create(:user, plan: GitHub::Plan.free)
      create(:billing_plan_subscription, :zuora, user: user, balance_in_cents: -15_00)
      seat_change = Billing::PlanChange::DataPackChange.new(user, total_packs: 1)

      assert_equal Billing::Money.new(0), seat_change.total_price
    end

    test "allows discount for full amount" do
      create(:asset_status, owner: @user, asset_packs: 3)
      @user.redeem_coupon create(:coupon, discount: 75)

      change = Billing::PlanChange::DataPackChange.new(@user, total_packs: 5)
      assert_equal Billing::Money.new(0), change.total_price
    end

    test "shows correct amount for coupons" do
      user = create :credit_card_user, plan: "free"
      user.redeem_coupon create :coupon, discount: GitHub::Plan.pro.cost

      change = Billing::PlanChange::DataPackChange.new(user, total_packs: 3)
      assert_equal Billing::Money.new(15_00), change.total_price
    end
  end
end
