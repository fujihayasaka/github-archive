# typed: true
# frozen_string_literal: true

require "test_helper"

module Billing
  class ProductUUIDTest < GitHub::BillingTestCase
    fixtures do
      @sponsors_listing_uuid = create(:billing_product_uuid, :sponsors_listing)
      @sponsors_tier_uuid = create(:billing_product_uuid, :sponsors_tier)
      @marketplace_listing_plan_uuid = create(:billing_product_uuid, :marketplace_listing_plan)
      @copilot_monthly_product_uuid = create(:billing_product_uuid, :copilot, billing_cycle: :month)
      @copilot_yearly_product_uuid = create(:billing_product_uuid, :copilot, billing_cycle: :year)
      @advanced_security_monthly_product_uuid = create(:billing_product_uuid, :advanced_security, billing_cycle: :month)
      @actions_uuid = create(:billing_product_uuid, :actions_rate_plan)
    end

    context "#same_listing?" do
      test "returns false when given something other than a product UUID" do
        refute @copilot_monthly_product_uuid.same_listing?(nil)
        refute @copilot_monthly_product_uuid.same_listing?(create(:sponsors_tier))
      end

      test "returns true when given a product UUID" do
        assert @copilot_monthly_product_uuid.same_listing?(@copilot_monthly_product_uuid)
        assert @copilot_monthly_product_uuid.same_listing?(@marketplace_listing_plan_uuid)
        assert @copilot_monthly_product_uuid.same_listing?(@sponsors_tier_uuid)
        assert @copilot_monthly_product_uuid.same_listing?(@sponsors_listing_uuid)
      end
    end

    context "for_zuora_product_rate_plan scope" do
      test "returns only product UUIDs with the specified Zuora product rate plan ID" do
        zuora_product_rate_plan_id = "8675309"
        uuid1 = create(:billing_product_uuid, zuora_product_rate_plan_id: zuora_product_rate_plan_id)
        uuid2 = create(:billing_product_uuid, zuora_product_rate_plan_id: "someOtherValue")

        result = Billing::ProductUUID.for_zuora_product_rate_plan(zuora_product_rate_plan_id)

        assert_includes result, uuid1
        refute_includes result, uuid2
      end
    end

    context "#rate_plan_charge_id_of_type?" do
      test "returns true for a rate plan charge ID in the specified section of the product UUID" do
        fee_rate_plan_charge_id = "somefeechargeid"
        non_fee_rate_plan_charge_id = "someflatchargeid"
        product_uuid = create(:billing_product_uuid, zuora_product_rate_plan_charge_ids: {
          fee: fee_rate_plan_charge_id,
          flat: non_fee_rate_plan_charge_id,
        })

        assert product_uuid.rate_plan_charge_id_of_type?(fee_rate_plan_charge_id, type: "fee")
        refute product_uuid.rate_plan_charge_id_of_type?(non_fee_rate_plan_charge_id, type: "fee")
      end

      test "returns false for a rate plan charge ID in the specified section when it's for a different product UUID" do
        fee_rate_plan_charge_id = "somefeechargeid"
        non_fee_rate_plan_charge_id = "someflatchargeid"
        product_uuid = create(:billing_product_uuid, zuora_product_rate_plan_charge_ids: {
          fee: fee_rate_plan_charge_id,
          flat: non_fee_rate_plan_charge_id,
        })
        other_product_uuid = create(:billing_product_uuid)

        refute other_product_uuid.rate_plan_charge_id_of_type?(fee_rate_plan_charge_id, type: "fee")
        refute other_product_uuid.rate_plan_charge_id_of_type?(non_fee_rate_plan_charge_id, type: "fee")
      end

      test "works with string and symbol keys" do
        rate_plan_charge_id = "somechargeid"
        product_uuid = create(:billing_product_uuid, zuora_product_rate_plan_charge_ids: {
          flat: rate_plan_charge_id,
        })

        assert product_uuid.rate_plan_charge_id_of_type?(rate_plan_charge_id, type: "flat")
        assert product_uuid.rate_plan_charge_id_of_type?(rate_plan_charge_id, type: :flat)
        refute product_uuid.rate_plan_charge_id_of_type?("someothervalue", type: "flat")
        refute product_uuid.rate_plan_charge_id_of_type?("someothervalue", type: :flat)
        refute product_uuid.rate_plan_charge_id_of_type?(rate_plan_charge_id, type: :someotherkey)
        refute product_uuid.rate_plan_charge_id_of_type?(rate_plan_charge_id, type: "someotherkey")
      end
    end

    context "#unit_name" do
      test "returns the unit name for a per unit product" do
        assert_equal "seat", @advanced_security_monthly_product_uuid.unit_name
        assert @advanced_security_monthly_product_uuid.per_unit?
      end

      test "returns nil for a flat fee product" do
        assert_nil @copilot_monthly_product_uuid.unit_name
        assert @copilot_monthly_product_uuid.flat_fee?
      end
    end

    context "#github_arr" do
      test "returns the annual recurring revenue for the monthly product uuid" do
        assert_equal @copilot_monthly_product_uuid.base_price * 12, @copilot_monthly_product_uuid.github_arr
      end

      test "returns the annual recurring revenue for the annual product uuid" do
        assert_equal @copilot_yearly_product_uuid.base_price, @copilot_yearly_product_uuid.github_arr
      end
    end

    context "as a subscribable" do
      context "base_price" do
        test "defaults to the uuid's billing cycle when no duration is specified" do
          yearly_uuid = create(:billing_product_uuid, :copilot, :yearly)
          _monthly_uuid = create(:billing_product_uuid, :copilot)

          yearly_price = yearly_uuid.charges.first["price"].to_d

          assert_equal yearly_price, yearly_uuid.base_price.to_d
        end

        test "raises a BillingError when there's no UUID record for the duration provided" do
          uuid = create(:billing_product_uuid)

          assert_raises(Billing::Public::BillingError, "no product record for the duration specified") do
            uuid.base_price(duration: "quarter")
          end
        end
      end
    end

    context "with_product_key scope" do
      test "filters by product_key" do
        result = Billing::ProductUUID.with_product_key(@sponsors_listing_uuid.product_key)
          .where(id: [@sponsors_listing_uuid, @sponsors_tier_uuid, @marketplace_listing_plan_uuid])

        assert_includes result, @sponsors_listing_uuid
        refute_includes result, @sponsors_tier_uuid
        refute_includes result, @marketplace_listing_plan_uuid
      end
    end

    context "sponsors_tiers scope" do
      test "does not include UUID for a Sponsors listing" do
        refute_includes Billing::ProductUUID.sponsors_tiers, @sponsors_listing_uuid
      end

      test "includes UUID for a Sponsors tier" do
        assert_includes Billing::ProductUUID.sponsors_tiers, @sponsors_tier_uuid
      end

      test "does not include UUID for a Marketplace listing plan" do
        refute_includes Billing::ProductUUID.sponsors_tiers, @marketplace_listing_plan_uuid
      end
    end

    context "sponsors scope" do
      test "includes UUID for a Sponsors listing" do
        assert_includes Billing::ProductUUID.sponsors, @sponsors_listing_uuid
      end

      test "includes UUID for a Sponsors tier" do
        assert_includes Billing::ProductUUID.sponsors, @sponsors_tier_uuid
      end

      test "does not include UUID for a Marketplace listing plan" do
        refute_includes Billing::ProductUUID.sponsors, @marketplace_listing_plan_uuid
      end
    end

    context "marketplace scope" do
      test "does not include UUID for a Sponsors listing" do
        refute_includes Billing::ProductUUID.marketplace, @sponsors_listing_uuid
      end

      test "does not include UUID for a Sponsors tier" do
        refute_includes Billing::ProductUUID.marketplace, @sponsors_tier_uuid
      end

      test "includes UUID for a Marketplace listing plan" do
        assert_includes Billing::ProductUUID.marketplace, @marketplace_listing_plan_uuid
      end
    end

    context "billable scope" do
      test "includes UUID for a Sponsors listing" do
        assert_includes Billing::ProductUUID.billable, @sponsors_listing_uuid
      end

      test "includes UUID for a Sponsors tier" do
        assert_includes Billing::ProductUUID.billable, @sponsors_tier_uuid
      end

      test "includes UUID for a Marketplace listing plan" do
        assert_includes Billing::ProductUUID.billable, @marketplace_listing_plan_uuid
      end
    end

    context "metered scope" do
      test "includes UUID for metered UUID" do
        assert_includes Billing::ProductUUID.metered, @actions_uuid
      end

      test "does not include UUID for non-metered UUID" do
        refute_includes Billing::ProductUUID.metered, @copilot_monthly_product_uuid
      end
    end

    context "#bill_on_trial_expiration?" do
      test "product trials bill on expiration" do
        copilot = create(:billing_product_uuid, :copilot)
        assert copilot.bill_on_trial_expiration?
      end

      test "advanced security trials do not bill on expiration" do
        advanced_security = create(:billing_product_uuid, :advanced_security)
        refute advanced_security.bill_on_trial_expiration?
      end
    end

    context "#matches_invoice_item?" do
      test "returns true when the invoice item charge name matches the product UUID" do
        invoice_item = Billing::Zuora::InvoiceItem.new(
          "chargeAmount" => 162.4,
          "chargeName" => "GitHub Advanced Security - Month"
        )
        assert @advanced_security_monthly_product_uuid.matches_invoice_item?(invoice_item)
      end

      test "returns false when the invoice item charge name doesn't match the product UUID" do
        invoice_item = Billing::Zuora::InvoiceItem.new(
          "chargeAmount" => 162.4,
          "chargeName" => "GitHub Advanced Security - Month"
        )
        refute @copilot_monthly_product_uuid.matches_invoice_item?(invoice_item)
      end

      test "returns true for Copilot Monthly Product UUID record when invoice is yearly and 'match_copilot_cycle' is not true" do
        invoice_item = Billing::Zuora::InvoiceItem.new(
          "chargeAmount" => 162.4,
          "chargeName" => "GitHub Copilot - Annual"
        )
        assert @copilot_monthly_product_uuid.matches_invoice_item?(invoice_item)
      end

      test "returns false for Copilot Monthly Product UUID record when invoice is yearly and 'match_copilot_cycle' is true" do
        invoice_item = Billing::Zuora::InvoiceItem.new(
          "chargeAmount" => 162.4,
          "chargeName" => "GitHub Copilot - Annual"
        )
        refute @copilot_monthly_product_uuid.matches_invoice_item?(invoice_item, match_copilot_cycle: true)
      end

      test "returns true for Copilot Yearly Product UUID record when invoice is yearly and 'match_copilot_cycle' is true" do
        invoice_item = Billing::Zuora::InvoiceItem.new(
          "chargeAmount" => 162.4,
          "chargeName" => "GitHub Copilot - Annual"
        )
        assert @copilot_yearly_product_uuid.matches_invoice_item?(invoice_item, match_copilot_cycle: true)
      end
    end
  end
end
