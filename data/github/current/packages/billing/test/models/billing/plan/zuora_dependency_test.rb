# typed: true
# frozen_string_literal: true

require "test_helper"

class ZuoraDependencyForGitHubPlanTest < GitHub::TestCase
  include GitHub::ZuoraTestHelper

  context "#sync_to_zuora" do
    test "creates product in zuora if one doesn't exist" do
      with_live_zuora("zuora/github_pro_plan_product") do
        plan = GitHub::Plan.pro

        assert_difference "Billing::ProductUUID.count", 2 do
          assert plan.sync_to_zuora
        end

        User::BillingDependency::PLAN_DURATIONS.each do |cycle|
          uuid = Billing::ProductUUID.find_by!(product_type: "github.plan", product_key: "pro", billing_cycle: cycle)
          assert uuid.zuora_product_id
          assert uuid.zuora_product_rate_plan_id
          assert uuid.zuora_product_rate_plan_charge_ids[:flat]
          refute uuid.zuora_product_rate_plan_charge_ids[:unit]
        end
      end
    end

    test "creates per seat in zuora if one doesn't exist" do
      with_live_zuora("zuora/github_business_plan_product") do
        plan = GitHub::Plan.business

        assert_difference "Billing::ProductUUID.count", 2 do
          assert plan.sync_to_zuora
        end

        User::BillingDependency::PLAN_DURATIONS.each do |cycle|
          uuid = Billing::ProductUUID.find_by!(product_type: "github.plan", product_key: "business", billing_cycle: cycle)
          assert uuid.zuora_product_id
          assert uuid.zuora_product_rate_plan_id
          refute uuid.zuora_product_rate_plan_charge_ids[:flat]
          assert uuid.zuora_product_rate_plan_charge_ids[:base_unit]
          assert uuid.zuora_product_rate_plan_charge_ids[:unit]
          if cycle == "month"
            refute uuid.zuora_product_rate_plan_charge_ids[:annual_discount]
          else
            assert uuid.zuora_product_rate_plan_charge_ids[:annual_discount]
          end
        end
      end
    end
  end

  context "#zuora_id" do
    test "grabs the zuora id from the product uuid record" do
      create(
        :billing_product_uuid,
        product_type: "github.plan",
        product_key: "pro",
        billing_cycle: "month",
        zuora_product_rate_plan_id: "123abc",
      )
      plan = GitHub::Plan.pro

      assert_equal "123abc", plan.zuora_id(cycle: User::BillingDependency::MONTHLY_PLAN)
    end
  end

  context "#zuora_product_name" do
    test "when business_plus plan it shows correct result" do
      plan = GitHub::Plan.business_plus

      assert_equal "GitHub Enterprise Cloud", plan.zuora_product_name
    end

    test "when team plan it shows correct result" do
      plan = GitHub::Plan.business

      assert_equal plan.zuora_product_name, "GitHub Team Plan"
    end
  end
end if GitHub.billing_enabled?
