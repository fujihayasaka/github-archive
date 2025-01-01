# typed: true
# frozen_string_literal: true

require "test_helper"

class Billing::Zuora::RatePlanChargeTest < GitHub::TestCase
  context ".for" do
    test "returns a OneTimeCharge if the charge is one time" do
      attributes = attributes_for(:zuora_rate_plan_charge, :one_time)
      assert Billing::Zuora::RatePlanCharge.for(attributes).class, Billing::Zuora::OneTimeCharge
    end

    test "returns a RatePlanCharge if the charge is recurring" do
      attributes = attributes_for(:zuora_rate_plan_charge, :recurring)
      assert Billing::Zuora::RatePlanCharge.for(attributes).class, Billing::Zuora::RatePlanCharge
    end

    test "returns a RatePlanCharge if the charge has a blank type" do
      attributes = attributes_for(:zuora_rate_plan_charge, type: nil)
      assert Billing::Zuora::RatePlanCharge.for(attributes).class, Billing::Zuora::RatePlanCharge
    end
  end

  context "#is_metered__c" do
    test "returns true when the charge is metered" do
      charge = build(:zuora_rate_plan_charge, :metered_ghec)
      assert_predicate charge, :is_metered__c?

      charge = build(:zuora_rate_plan_charge, IsMetered__c: "true")
      assert_predicate charge, :is_metered__c?

      charge = build(:zuora_rate_plan_charge, IsMetered__c: true)
      assert_predicate charge, :is_metered__c?
    end

    test "returns false when the charge is not metered" do
      charge = build(:zuora_rate_plan_charge)
      refute_predicate charge, :is_metered__c?

      charge = build(:zuora_rate_plan_charge, IsMetered__c: false)
      refute_predicate charge, :is_metered__c?

      charge = build(:zuora_rate_plan_charge, IsMetered__c: "false")
      refute_predicate charge, :is_metered__c?
    end
  end

  context "#active?" do
    test "returns true when there is no effective end date" do
      charge = build(:zuora_rate_plan_charge, effectiveEndDate: nil)
      assert charge.active?
    end

    test "returns true when the effective end date is in the future" do
      charge = build(:zuora_rate_plan_charge, effectiveEndDate: 1.month.from_now.strftime("%Y-%m-%d"))
      assert charge.active?
    end

    test "returns false when the effective end date is in the past" do
      charge = build(:zuora_rate_plan_charge, effectiveEndDate: 1.month.ago.strftime("%Y-%m-%d"))
      refute charge.active?
    end

    test "returns false when the effective end date is the current date" do
      charge = build(:zuora_rate_plan_charge, effectiveEndDate: "2020-10-24")

      travel_to GitHub::Billing.timezone.local(2020, 10, 24) do
        refute charge.active?
      end
    end
  end

  context "#starts_in_future?" do
    test "returns false when there is no effective start date" do
      charge = build(:zuora_rate_plan_charge, effectiveStartDate: nil)
      refute charge.starts_in_future?
    end

    test "returns true when the effective start date is in the future" do
      charge = build(:zuora_rate_plan_charge, effectiveStartDate: 1.month.from_now.strftime("%Y-%m-%d"))
      assert charge.starts_in_future?
    end

    test "returns false when the effective start date is in the past" do
      charge = build(:zuora_rate_plan_charge, effectiveStartDate: 1.month.ago.strftime("%Y-%m-%d"))
      refute charge.starts_in_future?
    end

    test "returns false when the effective start date is the current date" do
      charge = build(:zuora_rate_plan_charge, effectiveStartDate: "2020-10-24")

      travel_to GitHub::Billing.timezone.local(2020, 10, 24) do
        refute charge.starts_in_future?
      end
    end
  end

  context "annual?" do
    test "returns true when the billing period is annual" do
      charge = build(:zuora_rate_plan_charge, billingPeriod: "Annual")
      assert charge.annual?
    end

    test "returns false when the billing period is not annual" do
      charge = build(:zuora_rate_plan_charge, billingPeriod: "Monthly")
      refute charge.annual?
    end
  end

  context "one_time?" do
    test "returns true when the charge is a one time charge" do
      charge = build(:zuora_rate_plan_charge, :one_time)
      assert charge.one_time?
    end

    test "returns false when the charge is not a one time charge" do
      charge = build(:zuora_rate_plan_charge, :recurring)
      refute charge.one_time?
    end
  end

  context "usage?" do
    test "returns true when the charge is a usage charge" do
      charge = build(:zuora_rate_plan_charge, :usage)
      assert charge.usage?
    end

    test "returns false when the charge is not a usage charge" do
      charge = build(:zuora_rate_plan_charge)
      refute charge.usage?
    end
  end
end
