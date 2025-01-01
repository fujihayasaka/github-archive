# typed: true
# frozen_string_literal: true

require "test_helper"

class BillingZuoraProductTest < GitHub::TestCase
  include GitHub::ZuoraTestHelper

  context ".create" do
    test "sets Taxable to false until we start charging for taxes" do
      VCR.use_cassette("zuora/products/sync_not_taxable_to_zuora") do
        GitHub::Plan.pro.sync_to_zuora

        rate_plan_charge_id = GitHub::Plan.pro.zuora_charge_ids(cycle: "month")[:flat]

        response = GitHub.zuorest_client.get_product_rate_plan_charge(rate_plan_charge_id)
        refute response["Taxable"], "expected rate plan charge to not be taxable"
      end
    end

    test "correctly syncs base unit plans to Zuora" do
      mock_zuora = FakeZuora.mock

      Billing::ZuoraProduct.create \
        product_type: "github.plan",
        product_key: "business",
        product_name: "GitHub Team Plan",
        charges: [
          { type: :base_unit, default_quantity: 5, unit: "Seats", prices: { month: 5, year: 60 } },
          { type: :unit, unit: "Seats", prices: { month: 9, year: 108 } },
          { type: :annual_discount, unit: "Seats", prices: { year: 8.3333333 } },
        ]

      year_base_unit_charge = mock_zuora.charge_objects.find { |charge| charge[:ListPrice] == 60 }
      assert_equal 5, year_base_unit_charge[:DefaultQuantity]
      assert_equal "Per Unit Pricing", year_base_unit_charge[:ChargeModel]
      assert_equal "Seats", year_base_unit_charge[:UOM]

      charge_tier = year_base_unit_charge[:ProductRatePlanChargeTierData][:ProductRatePlanChargeTier].first
      assert_equal "Per Unit", charge_tier[:PriceFormat]
      assert_equal 60, charge_tier[:Price]
      assert_equal "USD", charge_tier[:Currency]

      year_unit_charge = mock_zuora.charge_objects.find { |charge| charge[:ListPrice] == 108 }
      assert_equal 0, year_unit_charge[:DefaultQuantity]

      annual_discount_charge = mock_zuora.charge_objects.find { |charge| charge[:ChargeModel] == "Discount-Percentage" }
      assert_equal 8.3333333, annual_discount_charge[:ProductRatePlanChargeTierData][:ProductRatePlanChargeTier].first[:DiscountPercentage]

      month_base_unit_charge = mock_zuora.charge_objects.find { |charge| charge[:ListPrice] == 5 }
      assert_equal 5,
        month_base_unit_charge[:ProductRatePlanChargeTierData][:ProductRatePlanChargeTier].first[:Price]

      month_unit_charge = mock_zuora.charge_objects.find { |charge| charge[:ListPrice] == 9 }
      assert_equal 9,
        month_unit_charge[:ProductRatePlanChargeTierData][:ProductRatePlanChargeTier].first[:Price]
    end

    test "correctly syncs flat fee plans to Zuora" do
      mock_zuora = FakeZuora.mock

      Billing::ZuoraProduct.create \
        product_type: "github.plan",
        product_key: "pro",
        product_name: "GitHub Developer Plan",
        charges: [
          { type: :flat, prices: { month: 7, year: 84 } },
        ]

      annual_charge = mock_zuora.charge_objects.find { |charge| charge[:ListPrice] == 84 }
      assert_equal "Flat Fee Pricing", annual_charge[:ChargeModel]

      charge_tier = annual_charge[:ProductRatePlanChargeTierData][:ProductRatePlanChargeTier].first
      assert_equal 84, charge_tier[:Price]
      assert_equal "USD", charge_tier[:Currency]
      assert_equal "Flat Fee", charge_tier[:PriceFormat]

      monthly_charge = mock_zuora.charge_objects.find { |charge| charge[:ListPrice] == 7 }
      assert_equal "Flat Fee Pricing", monthly_charge[:ChargeModel]
    end

    test "correctly syncs percentage discounts coupons to Zuora" do
      mock_zuora = FakeZuora.mock

      Billing::ZuoraProduct.create \
        product_type: "github.coupon",
        product_key: "percentage",
        product_name: "GitHub Percentage Discount",
        charges: [
          { type: :percentage_discount, prices: { month: 0, year: 0 } },
        ]

      monthly_charge = mock_zuora.charge_objects.find { |charge| charge[:ListPrice] == 0 }
      assert_equal "Discount-Percentage", monthly_charge[:ChargeModel]
      assert_equal "RECURRING", monthly_charge[:ApplyDiscountTo]
      assert_equal "subscription", monthly_charge[:DiscountLevel]

      # Discount calls should have a custom version header, as they need a more
      # updated version of the WSDL
      assert_equal Billing::ZuoraProduct::ZuoraSettings::DISCOUNT_WSDL_VERSION.to_s, mock_zuora.headers.last["X-Zuora-WSDL-Version"]
    end

    test "only applies discounts to non-discount GitHub products" do
      mock_zuora = FakeZuora.mock

      Billing::ZuoraProduct.create \
        product_type: "github.plan",
        product_key: "pro",
        product_name: "GitHub Developer Plan",
        charges: [
          { type: :flat, prices: { month: 7, year: 84 } },
        ]
      Billing::ZuoraProduct.create \
        product_type: "marketplace.listing_plan",
        product_key: "24",
        product_name: "Travis CI",
        charges: [
          { type: :flat, prices: { month: 7, year: 84 } },
        ]
      Billing::ZuoraProduct.create \
        product_type: "github.coupon",
        product_key: "percentage",
        product_name: "GitHub Discount",
        charges: [
          { type: :percentage_discount, prices: { month: 0, year: 0 } },
        ]

      monthly_discount_charge =
        mock_zuora.charge_objects.find do
          |charge| charge[:ChargeModel] == "Discount-Percentage" && charge[:BillingPeriod] == "Month"
        end
      annual_discount_charge =
        mock_zuora.charge_objects.find do
          |charge| charge[:ChargeModel] == "Discount-Percentage" && charge[:BillingPeriod] == "Annual"
        end
      monthly_discount_apply = monthly_discount_charge[:ProductDiscountApplyDetailData][:ProductDiscountApplyDetail]
      annual_discount_apply = annual_discount_charge[:ProductDiscountApplyDetailData][:ProductDiscountApplyDetail]

      gh_monthly_product =
        Billing::ProductUUID.find_by!(product_type: "github.plan", product_key: "pro", billing_cycle: User::BillingDependency::MONTHLY_PLAN)
      mp_monthly_product =
        Billing::ProductUUID.find_by!(product_type: "marketplace.listing_plan", product_key: "24", billing_cycle: User::BillingDependency::MONTHLY_PLAN)
      discount_monthly_product =
        Billing::ProductUUID.find_by!(product_type: "github.coupon", product_key: "percentage", billing_cycle: User::BillingDependency::MONTHLY_PLAN)
      gh_yearly_product =
        Billing::ProductUUID.find_by!(product_type: "github.plan", product_key: "pro", billing_cycle: User::BillingDependency::YEARLY_PLAN)
      mp_yearly_product =
        Billing::ProductUUID.find_by!(product_type: "marketplace.listing_plan", product_key: "24", billing_cycle: User::BillingDependency::YEARLY_PLAN)

      assert_includes annual_discount_apply, { AppliedProductRatePlanId: gh_yearly_product.zuora_product_rate_plan_id }
      refute_includes annual_discount_apply, { AppliedProductRatePlanId: gh_monthly_product.zuora_product_rate_plan_id }
      refute_includes annual_discount_apply, { AppliedProductRatePlanId: mp_yearly_product.zuora_product_rate_plan_id }

      assert_includes monthly_discount_apply, { AppliedProductRatePlanId: gh_monthly_product.zuora_product_rate_plan_id }
      refute_includes monthly_discount_apply, { AppliedProductRatePlanId: gh_yearly_product.zuora_product_rate_plan_id }
      refute_includes monthly_discount_apply, { AppliedProductRatePlanId: mp_monthly_product.zuora_product_rate_plan_id }
      refute_includes monthly_discount_apply, { AppliedProductRatePlanId: discount_monthly_product.zuora_product_rate_plan_id }
    end

    test "creates only the monthly product if yearly already exists" do
      with_live_zuora("zuora/github_zuora_product_plan") do
        create(
          :billing_product_uuid,
          zuora_product_id: "2c92c0f873e7ec1d0173e8ddc75f68c2",
          product_type: "github.plan",
          product_key: "pro",
          billing_cycle: "year",
        )
        plan = GitHub::Plan.pro

        assert_difference "Billing::ProductUUID.count", 1 do
          plan.sync_to_zuora
        end

        monthly_product = Billing::ProductUUID.find_by!(product_type: "github.plan", product_key: "pro", billing_cycle: User::BillingDependency::MONTHLY_PLAN)
        assert_equal "2c92c0f873e7ec1d0173e8ddc75f68c2", monthly_product.zuora_product_id
      end
    end

    test "creates only the yearly product if monthly already exists" do
      with_live_zuora("zuora/github_zuora_product_plan") do
        create(
          :billing_product_uuid,
          zuora_product_id: "2c92c0f873e7ec1d0173e8ddc75f68c2",
          product_type: "github.plan",
          product_key: "pro",
          billing_cycle: "month",
        )
        plan = GitHub::Plan.pro

        assert_difference "Billing::ProductUUID.count", 1 do
          plan.sync_to_zuora
        end

        yearly_product = Billing::ProductUUID.find_by!(product_type: "github.plan", product_key: "pro", billing_cycle: User::BillingDependency::YEARLY_PLAN)
        assert_equal "2c92c0f873e7ec1d0173e8ddc75f68c2", yearly_product.zuora_product_id
      end
    end

    test "uses custom attributes when provided" do
      mock_zuora = FakeZuora.mock
      slug = "travis-ci"
      name = "Travis CI"
      backdated_start_date = (GitHub::Billing.today - 1.year).to_s

      Billing::ZuoraProduct.create \
        product_type: "marketplace.listing_plan",
        product_key: "24",
        product_name: "Developer",
        charges: [
          { type: :unit, unit: "Seats", prices: { month: 9, year: 108 } },
        ],
        custom_product_params: {
          IntegratorSlug__c: slug,
          IntegratorName__c: name,
          ProductCategory__c: "marketplace",
          EffectiveStartDate: backdated_start_date
        }

      product = mock_zuora.calls[FakeZuora::CREATE_PRODUCT_PATH].first
      assert_equal name, product[:IntegratorName__c]
      assert_equal slug, product[:IntegratorSlug__c]
      assert_equal "marketplace", product[:ProductCategory__c]
      assert_equal backdated_start_date, product[:EffectiveStartDate]
    end

    test "creates charges without proration" do
      mock_zuora = FakeZuora.mock

      Billing::ZuoraProduct.create \
        product_type: "github.copilot",
        product_key: "v0",
        product_name: "GitHub Copilot",
        charges: [
          { type: :flat, prices: { month: 7, year: 84 }, prorate: { year: false } },
        ]

      monthly_uuid = Billing::ProductUUID.find_by!(product_type: "github.copilot", product_key: "v0", billing_cycle: "month")
      yearly_uuid = Billing::ProductUUID.find_by!(product_type: "github.copilot", product_key: "v0", billing_cycle: "year")

      assert monthly_uuid.charges.all? { |c| c.prorate == true }
      assert yearly_uuid.charges.all? { |c| c.prorate == false }
    end
  end

  test "creates the proper rate plans on a new product" do
    with_live_zuora("zuora/billing_period_alignment") do
      Billing::ZuoraProduct.create \
        product_type: "marketplace.listing_plan",
        product_key: "24",
        product_name: "Developer",
        charges: [
          { type: :unit, unit: "Seats", prices: { month: 9, year: 108 } },
        ]

      product_rate_plans = ::Billing::ProductUUID.where(product_key: "24")
      product_rate_plans.each do |rate_plan|
        response = GitHub.zuorest_client.get_product_rate_plan_charge(rate_plan.zuora_product_rate_plan_charge_ids[:unit])
        if response["Billing Period"] == "Month"
          assert_equal response["BillingPeriodAlignment"], "AlignToCharge"
        end
        if response["Billing Period"] == "Annual"
          assert_equal response["BillingPeriodAlignment"], "AlignToSubscriptionStart"
        end
      end
    end
  end
end if GitHub.billing_enabled?
