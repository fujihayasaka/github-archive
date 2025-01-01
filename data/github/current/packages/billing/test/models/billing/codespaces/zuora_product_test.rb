# typed: true
# frozen_string_literal: true

require "test_helper"

class Billing::Codespaces::ZuoraProductTest < GitHub::TestCase
  include GitHub::ZuoraTestHelper

  context ".storage_unit_cost" do
    test "returns Gigabyte hour cost from monthly cost" do
      # 31 days * 24 = 744 hours in month
      storage_unit_cost = Billing::Codespaces::ZuoraProduct::PRICE_PER_GB_MONTH.to_d / 31 / 24

      assert_equal storage_unit_cost, Billing::Codespaces::ZuoraProduct.storage_unit_cost
    end
  end

  context ".storage_unit_cost_in_cents" do
    test "returns Gigabyte hour cost in cents from monthly cost" do
      # 31 days * 24 = 744 hours in month
      storage_unit_cost = Billing::Codespaces::ZuoraProduct::PRICE_PER_GB_MONTH.to_d / 31 / 24
      storage_unit_cost_in_cents = storage_unit_cost * 100

      assert_equal storage_unit_cost_in_cents, Billing::Codespaces::ZuoraProduct.storage_unit_cost_in_cents
    end
  end

  context ".uuid" do
    test "returns the created produc UUID for codespaces" do
      with_live_zuora("zuora/github_codespaces_product") do
        assert_difference(-> { Billing::ProductUUID.count }, 1) do
          Billing::Codespaces::ZuoraProduct.sync_to_zuora
        end
      end

      uuid = Billing::Codespaces::ZuoraProduct.uuid

      assert_equal Billing::Codespaces::ZuoraProduct.product_type, uuid.product_type
      assert_equal Billing::Codespaces::ZuoraProduct.product_key, uuid.product_key
    end
  end

  context "#sync_to_zuora" do
    test "creates the product and associated rate plans if they don't exists" do
      with_live_zuora("zuora/github_codespaces_product") do
        assert_difference(-> { Billing::ProductUUID.count }, 1) do
          Billing::Codespaces::ZuoraProduct.sync_to_zuora
        end
      end
    end

    test "uses the existing product and associated rate plans if they exist" do
      with_live_zuora("zuora/github_codespaces_product_already_exist") do
        Billing::Codespaces::ZuoraProduct.sync_to_zuora

        assert_difference(-> { Billing::ProductUUID.count }, 0) do
          Billing::Codespaces::ZuoraProduct.sync_to_zuora
        end
      end
    end

    test "creates a rate plan for each eligible plan for bandwidth charges" do
      with_live_zuora("zuora/github_codespaces_product") do
        assert_difference(-> { Billing::ProductUUID.count }, 1) do
          Billing::Codespaces::ZuoraProduct.sync_to_zuora
        end
      end
      product_uuid = Billing::ProductUUID.find_by!(product_type: Billing::Codespaces::ZuoraProduct.product_type, product_key: Billing::Codespaces::ZuoraProduct.product_key)

      assert product_uuid.zuora_product_id
      assert product_uuid.zuora_product_rate_plan_id
      assert product_uuid.zuora_product_rate_plan_charge_ids[:compute]
      assert product_uuid.zuora_product_rate_plan_charge_ids[:storage]
    end
  end
end if GitHub.billing_enabled?
