# typed: true
# frozen_string_literal: true

require "test_helper"

class Billing::PackageRegistry::ZuoraProductTest < GitHub::TestCase
  include GitHub::ZuoraTestHelper

  context "#sync_to_zuora" do
    test "creates the product and associated rate plans if they don't exists" do
      with_live_zuora("zuora/github_package_registry_product") do
        assert_difference(-> { Billing::ProductUUID.count }, 1) do
          Billing::PackageRegistry::ZuoraProduct.sync_to_zuora
        end
      end
    end

    test "uses the existing product and associated rate plans if they exist" do
      with_live_zuora("zuora/github_package_registry_product_already_exist") do
        Billing::PackageRegistry::ZuoraProduct.sync_to_zuora

        assert_difference(-> { Billing::ProductUUID.count }, 0) do
          Billing::PackageRegistry::ZuoraProduct.sync_to_zuora
        end
      end
    end

    test "creates a rate plan for each eligible plan for bandwidth charges" do
      with_live_zuora("zuora/github_package_registry_product") do
        assert_difference(-> { Billing::ProductUUID.count }, 1) do
          Billing::PackageRegistry::ZuoraProduct.sync_to_zuora
        end
      end
      product_uuid = Billing::ProductUUID.find_by!(product_type: "github.package_registry", product_key: Billing::PackageRegistry::ZuoraProduct.product_key)

      assert_equal Billing::PackageRegistry::ZuoraProduct.product_name, product_uuid.name
      assert product_uuid.zuora_product_id
      assert product_uuid.zuora_product_rate_plan_id
      assert product_uuid.zuora_product_rate_plan_charge_ids[:bandwidth]
      refute product_uuid.zuora_product_rate_plan_charge_ids[:unit]

      charges = product_uuid.charges
      assert_equal 1, charges.count
      charge = charges.first
      assert_equal "overage", charge["type"]
      assert_equal "#{product_uuid.name} - #{product_uuid.product_key.titleize}", charge["name"]
      assert_equal "month", charge["billing_duration"]
      assert_equal product_uuid.zuora_product_rate_plan_charge_ids[:bandwidth], charge["zuora_product_rate_plan_charge_id"]
    end
  end
end if GitHub.billing_enabled?
