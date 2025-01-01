# typed: true
# frozen_string_literal: true

require "test_helper"

if GitHub.billing_enabled?
  class WhenAnOrgUpgradesToBusinessPlusTest < GitHub::TestCase
    test "removes coupon" do
      coupon = create :coupon, discount: 25
      org = create :credit_card_org, plan: "business", seats: 5
      org.redeem_coupon coupon

      pricing_model = Billing::PlanChange::PerSeatPricingModel.new org,
        new_plan: GitHub::Plan.business_plus
      pricing_model.switch(actor: org)

      assert_equal GitHub::Plan.business_plus.name, org.reload.plan.name
      refute org.has_an_active_coupon?
    end

    test "does not immediately expire newly redeemed coupon" do
      org = create(:organization, plan: "free")
      coupon = create(:coupon, discount: 1.0, plan: "business_plus")

      org.redeem_coupon(coupon.code)

      assert_equal GitHub::Plan.business_plus, org.reload.plan
      assert_equal coupon.id, org.coupon.id
    end

    test "changing plan_duration does not remove coupon" do
      coupon = create :coupon, discount: 25
      org = create :credit_card_org, plan: "business_plus"
      org.redeem_coupon coupon

      pricing_model = Billing::PlanChange::PerSeatPricingModel.new org,
        new_plan: GitHub::Plan.business_plus, plan_duration: "year"
      pricing_model.switch(actor: org)

      assert org.has_an_active_coupon?
      assert_equal GitHub::Plan.business_plus, org.reload.plan
    end
  end
end
