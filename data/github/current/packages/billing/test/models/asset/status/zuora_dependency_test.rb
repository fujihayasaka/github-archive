# typed: true
# frozen_string_literal: true

require "test_helper"

class ZuoraDependencyForAssetStatusTest < GitHub::TestCase
  context "#sync_to_zuora" do
    test "creates product in zuora if one doesn't exist" do
      VCR.use_cassette("zuora/github_lfs") do
        assert_difference "Billing::ProductUUID.count", 2 do
          assert Asset::Status.sync_to_zuora
        end

        User::BillingDependency::PLAN_DURATIONS.each do |cycle|
          uuid = Billing::ProductUUID.find_by!(product_type: "github.lfs", product_key: "v0", billing_cycle: cycle)
          assert uuid.zuora_product_id
          assert uuid.zuora_product_rate_plan_id
          assert uuid.zuora_product_rate_plan_charge_ids
          assert uuid.zuora_product_rate_plan_charge_ids[:unit]
        end
      end
    end

    test "generates charges for per unit plans" do
      per_unit_charges = [{
        type: :unit,
        prices: {
          year: Asset::Status.yearly_cost_in_dollars,
          month: Asset::Status.monthly_cost_in_dollars,
        },
        unit: "Seats",
      }]
      assert_equal per_unit_charges, Asset::Status.zuora_charges
    end
  end

  context "#zuora_id" do
    test "grabs the zuora id from the product uuid record" do
      create(
        :billing_product_uuid,
        product_type: "github.lfs",
        product_key: "v0",
        billing_cycle: "month",
        zuora_product_rate_plan_id: "123abc",
      )

      assert_equal "123abc", Asset::Status.zuora_id(cycle: User::BillingDependency::MONTHLY_PLAN)
    end
  end

  context "#zuora_charge_ids" do
    test "grabs the zuora charge ids from the product uuid record" do
      create(
        :billing_product_uuid,
        product_type: "github.lfs",
        product_key: "v0",
        billing_cycle: "month",
        zuora_product_rate_plan_charge_ids: { unit: "123unit" },
      )

      assert_equal "123unit", Asset::Status.zuora_charge_ids(cycle: User::BillingDependency::MONTHLY_PLAN)[:unit]
    end
  end
end if GitHub.billing_enabled?
