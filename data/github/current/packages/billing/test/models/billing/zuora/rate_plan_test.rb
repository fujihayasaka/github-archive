# typed: true
# frozen_string_literal: true

require "test_helper"

class Billing::Zuora::RatePlanTest < GitHub::TestCase
  context "#rate_plan_charges" do
    test "returns an array of rate plan charges" do
      rate_plan = build(:zuora_rate_plan, :with_rate_plan_charges)

      assert_equal rate_plan.rate_plan_charges.count, 2
      assert_equal rate_plan.rate_plan_charges.first.class, Billing::Zuora::RatePlanCharge
    end
  end

  context "#active?" do
    test "returns true if any rate plan charges are active" do
      rate_plan = build(:zuora_rate_plan, :with_rate_plan_charges)

      inactive_charge = attributes_for(:zuora_rate_plan_charge, :inactive)
      active_charge = attributes_for(:zuora_rate_plan_charge)

      rate_plan = build(:zuora_rate_plan, ratePlanCharges: [inactive_charge, active_charge])

      assert rate_plan.active?
    end

    test "returns false if all rate plan charges are inactive" do
      rate_plan = build(:zuora_rate_plan, :with_rate_plan_charges)

      inactive_charge = attributes_for(:zuora_rate_plan_charge, :inactive)

      rate_plan = build(:zuora_rate_plan, ratePlanCharges: [inactive_charge])

      refute rate_plan.active?
    end

    test "returns false if the rate plan was scheduled for removal" do
      rate_plan = build(:zuora_rate_plan, :with_rate_plan_charges, lastChangeType: "Remove")

      refute rate_plan.active?
    end
  end

  context "#one_time_plan?" do
    test "returns true if any rate plan charges are one time" do
      rate_plan = build(:zuora_rate_plan, :with_rate_plan_charges)
      rate_plan.rate_plan_charges << build(:zuora_rate_plan_charge, :one_time)

      assert rate_plan.one_time_plan?
    end

    test "returns false if all rate plan charges are recurring" do
      rate_plan = build(:zuora_rate_plan, :with_rate_plan_charges)

      refute rate_plan.one_time_plan?
    end
  end

  context "#scheduled_for_removal?" do
    test "returns true when the last change type is Remove" do
      rate_plan = build(:zuora_rate_plan, lastChangeType: "Remove")

      assert rate_plan.scheduled_for_removal?
    end

    test "returns false when the last change type is not Remove" do
      rate_plan = build(:zuora_rate_plan)

      refute rate_plan.scheduled_for_removal?
    end
  end
end
