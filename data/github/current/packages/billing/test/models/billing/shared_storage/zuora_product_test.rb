# typed: true
# frozen_string_literal: true

require "test_helper"

class Billing::SharedStorage::ZuoraProductTest < GitHub::TestCase
  include GitHub::ZuoraTestHelper

  context "#sync_to_zuora" do
    test "creates the product and associated rate plans if they don't exists" do
      with_live_zuora("zuora/github_shared_storage_product") do
        assert_difference(-> { Billing::ProductUUID.count }, 1) do
          Billing::SharedStorage::ZuoraProduct.sync_to_zuora
        end
      end
    end

    test "uses the existing product and associated rate plans if they exist" do
      with_live_zuora("zuora/github_shared_storage_product_already_exist") do
        Billing::SharedStorage::ZuoraProduct.sync_to_zuora

        assert_difference(-> { Billing::ProductUUID.count }, 0) do
          Billing::SharedStorage::ZuoraProduct.sync_to_zuora
        end
      end
    end

    test "creates a rate plan for storage charges based on tiers and store each tier in the UUID" do
      with_live_zuora("zuora/github_shared_storage_product") do
        assert_difference(-> { Billing::ProductUUID.count }, 1) do
          Billing::SharedStorage::ZuoraProduct.sync_to_zuora
        end
      end

      product_uuid = Billing::ProductUUID.find_by!(
        product_type: Billing::SharedStorage::ZuoraProduct.product_type,
        product_key: Billing::SharedStorage::ZuoraProduct.product_key,
      )
      assert product_uuid.zuora_product_id
      assert product_uuid.zuora_product_rate_plan_id
      assert product_uuid.zuora_product_rate_plan_charge_ids[:usage]

      charges = product_uuid.charges
      assert_equal 1, charges.count
      charge = T.must(charges.first)
      assert_equal "overage", charge.type
      assert_equal "#{product_uuid.name}", charge.name
      assert_equal "month", charge.billing_duration
      assert_equal product_uuid.zuora_product_rate_plan_charge_ids[:usage], charge.zuora_product_rate_plan_charge_id
    end
  end
end if GitHub.billing_enabled?
