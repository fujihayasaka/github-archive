# typed: true
# frozen_string_literal: true

require "test_helper"

class BillingPlatformEnabledProductTest < GitHub::TestCase
  include DogstatsTestHelpers

  fixtures do
    @billing_platform_enabled_products = create :billing_platform_enabled_product
    @customer = @billing_platform_enabled_products.customer
  end

  test ".in_a_cohort scope only returns users with a cohort" do
    in_a_cohort = FactoryBot.create(:billing_platform_enabled_product, cohort_name: "Cohort exists")
    not_in_a_cohort = FactoryBot.create(:billing_platform_enabled_product, cohort_name: nil)

    assert_includes(
      BillingPlatformEnabledProduct.in_a_cohort,
      in_a_cohort,
    )

    refute_includes(
      BillingPlatformEnabledProduct.in_a_cohort,
      not_in_a_cohort,
    )
  end

  test "instance cannot be created without a customer id" do
    assert_raises ActiveRecord::RecordInvalid do
      BillingPlatformEnabledProduct.create!
    end
  end

  context "product getter methods" do
    test "returns false if the value is nil" do
      assert_equal false, @billing_platform_enabled_products.actions
    end

    test "returns false if the value is false" do
      @billing_platform_enabled_products.update!(copilot: false)
      assert_equal false, @billing_platform_enabled_products.copilot
    end

    test "returns true if the value is true" do
      @billing_platform_enabled_products.update!(codespaces: true)
      assert @billing_platform_enabled_products.codespaces
    end
  end

  context "#sync_customer_in_billing_platform" do
    test "calls UpdateCustomerInBillingPlatformJob on update" do
      assert_enqueued_jobs 1, only: Billing::UpdateCustomerInBillingPlatformJob do
        @billing_platform_enabled_products.update!(copilot: true)
        assert_enqueued_with(job: Billing::UpdateCustomerInBillingPlatformJob, args: [@customer])
      end
    end

    test "calls UpdateCustomerInBillingPlatformJob on create" do
      # the job is called once when a customer is created
      # and again when a billing_platform_enabled_product record is created for a customer
      assert_enqueued_jobs 1, only: Billing::UpdateCustomerInBillingPlatformJob do
        billing_platform_enabled_products = create :billing_platform_enabled_product
        customer = billing_platform_enabled_products.customer
        assert_enqueued_with(job: Billing::UpdateCustomerInBillingPlatformJob, args: [customer])
      end
    end
  end

  context "#instrument_billed_via_billing_platform" do
    test "increments the update count when called" do
      @billing_platform_enabled_products.update!(codespaces: false)

      assert_dogstats_increment(1, "billing.billing_platform_enabled_products_updated.count")
    end
  end

  context "#all_enabled_products" do
    test "returns an array of all enabled products" do
      @billing_platform_enabled_products.update!(codespaces: true, actions: true, copilot: true)

      assert_same_elements %w[actions codespaces copilot], @billing_platform_enabled_products.all_enabled_products
    end

    test "returns an empty array if no products are enabled" do
      assert_equal [], @billing_platform_enabled_products.all_enabled_products
    end
  end
end
