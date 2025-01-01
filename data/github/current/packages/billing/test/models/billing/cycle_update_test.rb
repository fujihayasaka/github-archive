# typed: true
# frozen_string_literal: true

require "test_helper"

class Billing::CycleUpdateTest < GitHub::BillingTestCase
  include GitHub::ZuoraTestHelper

  fixtures do
    at_time(2014, 2, 1, 18, 15) do
      @yearly_user = create :credit_card_user,
        billed_on: GitHub::Billing.today + 12.months,
        plan_duration: "year",
        plan: :small

      @monthly_user = create :credit_card_user,
        billed_on: GitHub::Billing.today + 1.month,
        plan_duration: "month",
        plan: :small
    end
  end

  test "switches monthly_user to yearly" do
    Billing::CycleUpdate.new(@monthly_user, "year").perform

    @monthly_user.reload
    assert_equal "year", @monthly_user.plan_duration
  end

  test "switches yearly_user to monthly" do
    Billing::CycleUpdate.new(@yearly_user, "month").perform

    @yearly_user.reload
    assert_equal "month", @yearly_user.plan_duration
  end

  test "schedules a downgrade to monthly when zuora" do
    plan_subscription = create(:billing_plan_subscription, :zuora)
    user = plan_subscription.user
    user.update(plan_duration: "year", plan: "pro")

    Billing::CycleUpdate.new(user, "month").perform

    user.reload
    assert_equal "year", user.plan_duration
  end

  test "switching saves the account" do
    @yearly_user.expects(:save!).at_least_once.returns(true)
    Billing::CycleUpdate.new(@yearly_user, "month").perform
  end

  test "returns early if nothing changed" do
    @yearly_user.expects(:save!).never
    Billing::CycleUpdate.new(@yearly_user, "year").perform
  end

  test "returns early if account is invoiced" do
    @yearly_user.billing_type = "invoice"
    Billing::CycleUpdate.new(@yearly_user, "month").perform

    @yearly_user.reload
    assert_equal "year", @yearly_user.plan_duration
  end

  test "refunds discounted amount if coupon present" do
    plan = GitHub::Plan.pro
    coupon = create :coupon, code: "coupon-time", discount: 0.5, limit: 50
    at_time(2014, 2, 1, 18, 15) do
      @yearly_with_coupon = create :user,
        billing_type: "card",
        billed_on: GitHub::Billing.today + 12.months,
        plan: plan,
        plan_duration: "year"

      @yearly_with_coupon.redeem_coupon "coupon-time"
    end

    at_time(2014, 6, 1, 18, 15) do
      cycle_update = Billing::CycleUpdate.new(@yearly_with_coupon, "month")
      full_refund = -1 * @yearly_with_coupon.plan.cost * 7 * 100
      discount_applied = full_refund * coupon.discount
      assert_equal discount_applied, cycle_update.refund_in_cents
    end
  end

  test "switch -> monthly calculates refund amount correctly" do
    # User paid $12 * 12 months in Feb
    # Feb - Mar, Mar - Apr, Apr - May, May - June - paid for
    # + June - July - paying for now
    # Five months paid for = 7 months refunded
    at_time(2014, 6, 1, 18, 15) do
      cycle_update = Billing::CycleUpdate.new(@yearly_user, "month")
      assert_equal 0 - (7 * 12 * 100), cycle_update.refund_in_cents
    end
  end

  test "switch -> monthly should not charge if months left is zero" do
    at_time(2015, 1, 28, 18, 15) do
      cycle_update = Billing::CycleUpdate.new(@yearly_user, "month")
      assert_equal 0, cycle_update.refund_in_cents
    end
  end

  test "switch -> monthly should adjust billed_on correctly" do
    switch_to_monthly

    assert_equal Date.new(2014, 7, 1), @yearly_user.billed_on
  end

  test "switch -> monthly adjusts billed_on based on original billed_on" do
    at_time(2014, 6, 15, 18, 15) do
      Billing::CycleUpdate.new(@yearly_user, "month").perform
    end

    assert_equal Date.new(2014, 7, 1), @yearly_user.billed_on
  end

  test "switch -> monthly should alter subscription correctly" do
    switch_to_monthly

    assert_equal "month", @yearly_user.plan_duration
  end

  test "rapid-fire cycling doesn't refund anything unnecessarily" do
    assert_equal Date.new(2015, 2, 1), @yearly_user.billed_on

    at_time(2015, 1, 1, 18, 15) do
      Billing::CycleUpdate.new(@yearly_user, "month").perform
    end

    assert_equal Date.new(2015, 2, 1), @yearly_user.billed_on
    assert_equal "month", @yearly_user.plan_duration

    at_time(2015, 1, 1, 21, 15) do
      Billing::CycleUpdate.new(@yearly_user, "year").perform
    end

    assert_equal Date.new(2015, 2, 1), @yearly_user.billed_on
    assert_equal "year", @yearly_user.plan_duration
  end

  context "#next_billed_on" do
    test "is billed_on for a customer with billed_on already in the future" do
      billed_on = GitHub::Billing.today + 15.days
      user = create :user, plan: "small", plan_duration: "month",
        billed_on: billed_on

      cycle_update = Billing::CycleUpdate.new(user, "year")
      assert_equal billed_on, cycle_update.next_billed_on
    end

    test "is today for a customer with billed_on in the past" do
      at_time(2015, 1, 1, 21, 15) do
        billed_on = GitHub::Billing.today - 2.months
        user = create :user, plan: "small", plan_duration: "month",
          billed_on: billed_on

        cycle_update = Billing::CycleUpdate.new(user, "year")
        assert_equal Date.new(2015, 1, 1), cycle_update.next_billed_on
      end
    end

    test "is next monthly billed_on when moving from yearly to monthly" do
      at_time(2015, 1, 1, 21, 15) do
        billed_on = Date.new(2015, 8, 15)
        user = create :user, plan: "small", plan_duration: "year",
          billed_on: billed_on

        cycle_update = Billing::CycleUpdate.new(user, "month")
        assert_equal Date.new(2015, 1, 15), cycle_update.next_billed_on
      end
    end
  end

  def switch_to_monthly(user = @yearly_user)
    at_time(2014, 6, 1, 18, 15) do
      Billing::CycleUpdate.new(@yearly_user, "month").perform
    end
  end
end
