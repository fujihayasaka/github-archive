# typed: true
# frozen_string_literal: true

require "test_helper"

class Billing::MeteredProductTest < GitHub::TestCase
  setup do
    @default_plan = {
      effective_on: 10.days.ago,
      github_plans: %w[free pro],
      overages: {
        price: "0.08",
        unit_of_measure: {
          name: "Hours",
          scale: 3600
        }
      }
    }

    @sku_options = {
      name: "basic_linux",
      unit_of_measure: "Seconds",
    }
  end

  context ".all" do
    test "returns all MeteredProducts" do
      all = Billing::MeteredProduct.all

      assert_operator all.length, :>, 0
      all.each { |product| assert_instance_of Billing::MeteredProduct, product }
    end
  end

  context ".exists?" do
    test "returns true for a valid MeteredProduct" do
      assert Billing::MeteredProduct.exists?("actions")
    end

    test "returns false for an invalid MeteredProduct" do
      refute Billing::MeteredProduct.exists?("does_not_exist")
    end
  end

  context ".find" do
    test "returns a valid MeteredProduct" do
      product = Billing::MeteredProduct.find("actions")
      refute_nil product

      assert_equal "actions", product.name
      assert_predicate product, :enabled?
      assert_equal "shared", product.budget_group
      assert_equal "shared", product.prepaid_budget_group

      assert_operator product.skus.length, :>, 0

      sku = product.skus["macos"]
      refute_nil sku

      assert_equal "macos", sku.name
      assert_equal "Minutes", sku.unit_of_measure

      assert_operator sku.rate_plans.length, :>, 0

      rate_plan = sku.rate_plan_for(plan: GitHub::Plan.pro)
      refute_nil rate_plan

      assert_equal BigDecimal("0.008"), rate_plan.overage_price
      assert_equal "Minutes", rate_plan.overages.unit_of_measure.name
      assert_equal 10.0, rate_plan.multiplier
    end

    test "raises UnknownProductError for an invalid product" do
      assert_raises(Billing::MeteredProduct::UnknownProductError) do
        Billing::MeteredProduct.find("not_valid")
      end
    end
  end

  context ".usage_uuid" do
    test "returns UUID hash for given unique ID" do
      assert_equal "296a5f66-e8c3-306b-9d89-938d1c368c99", Billing::MeteredProduct.usage_uuid("123")
      assert_equal "596b79dc-00dd-3991-a72f-d3696c38c64f", Billing::MeteredProduct.usage_uuid("")
    end

    test "raises error if unique ID is nil" do
      assert_raises TypeError do
        Billing::MeteredProduct.usage_uuid(nil)
      end
    end
  end

  context "Sku#rate_plan_for" do
    test "as_of only consider rate_plans that are valid as of the given date" do
      earlier_rate_plan = @default_plan.merge \
        effective_on: @default_plan[:effective_on] - 10.days

      sku = Billing::MeteredProduct::Sku.new \
        **@sku_options.merge(rate_plans: [@default_plan, earlier_rate_plan])

      assert_equal @default_plan[:effective_on], sku.rate_plan_for.effective_on
      assert_equal earlier_rate_plan[:effective_on],
        sku.rate_plan_for(as_of: @default_plan[:effective_on] - 5.days).effective_on
    end

    test "returns nil if as_of is given and in the past of all effective_on" do
      sku = Billing::MeteredProduct::Sku.new(**@sku_options.merge(rate_plans: [@default_plan]))
      date = @default_plan[:effective_on] - 1.day

      assert_nil sku.rate_plan_for(as_of: date)
      refute_nil sku.rate_plan_for
    end
  end

  context ".effective_rate_plan_for" do
    test "returns valid RatePlan object" do
      rate_plan = Billing::MeteredProduct.effective_rate_plan_for(product: :actions, sku: :linux)
      refute_nil rate_plan

      assert_equal BigDecimal("0.008"), rate_plan.overage_price
      assert_equal "Minutes", rate_plan.overages.unit_of_measure.name
      assert_equal 1.0, rate_plan.multiplier
    end

    test "for actions product and macos sku" do
      rate_plan = Billing::MeteredProduct.effective_rate_plan_for(product: :actions, sku: :macos)
      assert_equal BigDecimal("0.008"), rate_plan.overage_price
      assert_equal 10.0, rate_plan.multiplier
    end

    test "for packages product and default sku" do
      rate_plan = Billing::MeteredProduct.effective_rate_plan_for(product: :packages, sku: :default)
      assert_equal BigDecimal("0.5"), rate_plan.overage_price
      assert_equal BigDecimal(1), rate_plan.multiplier
    end

    test "for shared storage product and default sku" do
      rate_plan = Billing::MeteredProduct.effective_rate_plan_for(product: :shared_storage, sku: :default)
      assert_equal BigDecimal("0.000000328"), rate_plan.overage_price
      assert_equal BigDecimal(1), rate_plan.multiplier
    end

    test "raises exception if product name is not valid" do
      assert_raises(Billing::MeteredProduct::UnknownProductError) do
        Billing::MeteredProduct.effective_rate_plan_for(product: :invalid_product, sku: :any_sku)
      end
    end

    test "raises exception if sku is not in the product" do
      assert_raises(Billing::MeteredProduct::UnknownProductSkuError) do
        Billing::MeteredProduct.effective_rate_plan_for(product: :actions, sku: :invalid_sku)
      end
    end

    test "calls rate_plan_for twice if first returns nil" do
      sku = Billing::MeteredProduct::Sku.new(**@sku_options.merge(rate_plans: [@default_plan]))
      Billing::MeteredProduct.stubs(:find).returns(stub(skus: stub(fetch: sku)))
      date = @default_plan[:effective_on] - 1.day

      sku.expects(:rate_plan_for).with(account: nil, as_of: date).once
      sku.expects(:rate_plan_for).with(account: nil).once

      Billing::MeteredProduct.effective_rate_plan_for(product: :packages, sku: :default, date: date)
    end
  end
end if GitHub.billing_enabled?
