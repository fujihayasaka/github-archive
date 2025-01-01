# typed: true
# frozen_string_literal: true

require "test_helper"

class ZuoraDependencyForMarketplaceListingPlanTest < GitHub::TestCase
  context "#zuora_id" do
    test "grabs the zuora id from the product uuid record" do
      plan = create(:marketplace_listing_plan)
      Billing::ProductUUID.destroy_all
      create(
        :billing_product_uuid,
        product_type: "marketplace.listing_plan",
        product_key: plan.id.to_s,
        billing_cycle: "month",
        zuora_product_rate_plan_id: "123abc",
      )

      assert_equal "123abc", plan.zuora_id(cycle: User::BillingDependency::MONTHLY_PLAN)
    end
  end

  context "#zuora_charges" do
    test "generates charges for flat fee plans" do
      plan = create(:marketplace_listing_plan)

      flat_fee_charges = [{
        type: :flat,
        prices: {
          year: plan.yearly_price_in_dollars,
          month: plan.monthly_price_in_dollars,
        },
      }]
      assert_equal flat_fee_charges, plan.zuora_charges
    end

    test "generates charges for per unit plans" do
      plan = create :marketplace_listing_plan, :per_unit

      per_unit_charges = [{
        type: :unit,
        prices: {
          year: plan.yearly_price_in_dollars,
          month: plan.monthly_price_in_dollars,
        },
        unit: "Seats",
      }]
      assert_equal per_unit_charges, plan.zuora_charges
    end
  end

  context "#sync_to_zuora" do
    test "creates product in zuora if one doesn't exist" do
      VCR.use_cassette("zuora/marketplace_plan_product") do
        plan = create(:marketplace_listing_plan)

        assert_difference "Billing::ProductUUID.count", 2 do
          plan.sync_to_zuora
        end

        User::BillingDependency::PLAN_DURATIONS.each do |cycle|
          uuid = Billing::ProductUUID.find_by!(product_type: "marketplace.listing_plan", product_key: plan.id, billing_cycle: cycle)
          assert uuid.zuora_product_id
          assert uuid.zuora_product_rate_plan_id
          assert uuid.zuora_product_rate_plan_charge_ids[:flat]
          refute uuid.zuora_product_rate_plan_charge_ids[:unit]
        end
      end
    end

    test "creates per seat in zuora if one doesn't exist" do
      VCR.use_cassette("zuora/marketplace_per_seat_product") do
        plan = create(:marketplace_listing_plan, :per_unit)

        assert_difference "Billing::ProductUUID.count", 2 do
          plan.sync_to_zuora
        end

        User::BillingDependency::PLAN_DURATIONS.each do |cycle|
          uuid = Billing::ProductUUID.find_by!(product_type: "marketplace.listing_plan", product_key: plan.id, billing_cycle: cycle)
          assert uuid.zuora_product_id
          assert uuid.zuora_product_rate_plan_id
          refute uuid.zuora_product_rate_plan_charge_ids[:flat]
          assert uuid.zuora_product_rate_plan_charge_ids[:unit]
        end
      end
    end

    test "creates product with custom attributes for integrator" do
      mock_zuora = FakeZuora.mock
      plan = create(:marketplace_listing_plan, :per_unit)

      plan.sync_to_zuora

      product = mock_zuora.calls[FakeZuora::CREATE_PRODUCT_PATH].first
      assert_equal plan.listing.name, product[:IntegratorName__c]
      assert_equal plan.listing.slug, product[:IntegratorSlug__c]
      assert_equal "marketplace", product[:ProductCategory__c]
    end
  end

  context "#matches_invoice_item?" do
    test "returns false if invoice_item does not contain listing_plan's listing name" do
      plan = create(:marketplace_listing_plan)
      invoice_item = Billing::Zuora::InvoiceItem.new(
        "chargeName" => "Not a matching charge name",
      )
      refute plan.matches_invoice_item?(invoice_item)
    end

    test "returns true if invoice_item contains listing_plan's listing name" do
      plan = create(:marketplace_listing_plan)
      invoice_item = Billing::Zuora::InvoiceItem.new(
        "chargeName" => "#{plan.listing.name} - Hello!",
      )
      assert plan.matches_invoice_item?(invoice_item)
    end
  end
end if GitHub.billing_enabled?
