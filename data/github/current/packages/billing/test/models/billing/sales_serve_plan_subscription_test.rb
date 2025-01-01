# typed: true
# frozen_string_literal: true

require "test_helper"

class BillingSalesServePlanSubscriptionTest < GitHub::TestCase
  include DogstatsTestHelpers

  fixtures do
    @business = create(:business)
    @azure_business = create(:business, :with_azure_subscription)
  end

  context "#zuora_rate_plan_charge_number" do
    test "returns nil when the product rate plan charge ID doesn't match" do
      plan_subscription = create(:billing_sales_serve_plan_subscription)

      assert_nil plan_subscription.zuora_rate_plan_charge_number(
        product_rate_plan_charge_id: "mismatch",
      )
    end

    test "returns the rate plan charge number if there's a product rate plan charge ID match" do
      rate_plan_charges = {
        "matching-id" => { number: "123" },
      }
      plan_subscription = create(:billing_sales_serve_plan_subscription, zuora_rate_plan_charges: rate_plan_charges)

      assert_equal "123", plan_subscription.zuora_rate_plan_charge_number(
        product_rate_plan_charge_id: "matching-id",
      )
    end
  end

  context "education_bundle?" do
    test "returns false when not on an education bundle" do
      plan_subscription = build :billing_sales_serve_plan_subscription

      refute plan_subscription.education_bundle?
    end

    test "returns true when on an education bundle" do
      plan_subscription = build :billing_sales_serve_plan_subscription,
        education_bundle: :essential

      assert plan_subscription.education_bundle?
    end
  end

  context "validations zuora ids" do
    test "requires ids for zuora customers with charges" do
      plan_sub = build :billing_sales_serve_plan_subscription,
        customer: @business.customer,
        zuora_rate_plan_charges: { charge_one: 4242 },
        zuora_subscription_id: nil,
        zuora_subscription_number: nil

      plan_sub.save

      error_columns = plan_sub.errors.map(&:attribute)
      assert_includes error_columns, :zuora_subscription_id
      assert_includes error_columns, :zuora_subscription_number
    end

    test "doesn't require ids for subscription without charges" do
      plan_sub = build :billing_sales_serve_plan_subscription,
        customer: @business.customer,
        zuora_rate_plan_charges: {},
        zuora_subscription_id: nil,
        zuora_subscription_number: nil

      assert plan_sub.save

      assert_empty plan_sub.errors
    end

    test "doesn't require ids for customers billed through azure" do
      plan_sub = build :billing_sales_serve_plan_subscription,
        customer: @azure_business.customer,
        zuora_subscription_id: nil,
        zuora_subscription_number: nil

      assert plan_sub.save

      assert_empty plan_sub.errors
    end
  end

  context "#ghe_rate_plan_charge" do
    test "it returns the correct rate plan charge" do
      plan_sub = create(
        :billing_sales_serve_plan_subscription,
      )

      create(:plan_subscription_zuora_rate_plan_charge, plan_subscription: plan_sub, product_rate_plan_charge_id: GitHub.zuora_sales_serve_ghe_product_charge_ids.first, payload: { effectiveStartDate: GitHub::Billing.today - 1.day, price: 100.0 })
      target = create(:plan_subscription_zuora_rate_plan_charge, plan_subscription: plan_sub, product_rate_plan_charge_id: GitHub.zuora_sales_serve_ghas_product_charge_ids.first, payload: { effectiveStartDate: GitHub::Billing.today - 1.day, price: 200.00 })

      ghe_rate_plan_charge = T.must(plan_sub.ghas_rate_plan_charge)
      assert_equal ghe_rate_plan_charge.product_rate_plan_charge_id, GitHub.zuora_sales_serve_ghas_product_charge_ids.first
      assert_equal ghe_rate_plan_charge.price, 200.0
    end
  end

  context "#ghas_rate_plan_charge" do
    test "it returns the correct rate plan charge" do
      plan_sub = create(
        :billing_sales_serve_plan_subscription,
      )

      target = create(:plan_subscription_zuora_rate_plan_charge, plan_subscription: plan_sub, product_rate_plan_charge_id: GitHub.zuora_sales_serve_ghe_product_charge_ids.first, payload: { effectiveStartDate: GitHub::Billing.today - 1.day, price: 100.0 })
      create(:plan_subscription_zuora_rate_plan_charge, plan_subscription: plan_sub, product_rate_plan_charge_id: GitHub.zuora_sales_serve_ghas_product_charge_ids.first, payload: { effectiveStartDate: GitHub::Billing.today - 1.day, price: 200.00 })

      ghe_rate_plan_charge = T.must(plan_sub.ghe_rate_plan_charge)
      assert_equal ghe_rate_plan_charge.product_rate_plan_charge_id, GitHub.zuora_sales_serve_ghe_product_charge_ids.first
      assert_equal ghe_rate_plan_charge.price, 100.0
    end
  end

  context "#update" do
    test "touches customer on updates" do
      plan_sub = create :billing_sales_serve_plan_subscription, customer: @business.customer

      travel_to 1.hour.from_now do
        assert_changes(-> { @business.customer.updated_at }) do
          plan_sub.update!(zuora_subscription_number: "A1234")
          plan_sub.reload
        end
      end
    end
  end

  context "#sync_customer_in_billing_platform" do
    test "does not enqueue sync job if customer is not billed via Billing Platform" do
      @business.customer.update!(billed_via_billing_platform: false)

      # Process any enqueued jobs
      perform_enqueued_jobs(only: [Billing::UpdateCustomerInBillingPlatformJob])

      assert_enqueued_jobs(0, only: Billing::UpdateCustomerInBillingPlatformJob) do
        plan_sub = create(:billing_sales_serve_plan_subscription, customer: @business.customer)
      end

      assert_dogstats_increment(0, "plan_subscription.billing_platform_update_customer_called")
    end

    test "does not enqueue sync job if feature flag is not enabled" do
      disable_feature_flag(:sync_billing_platform_customers_on_subscription_changes)
      @business.customer.update!(billed_via_billing_platform: true)

      # Process any enqueued jobs
      perform_enqueued_jobs(only: [Billing::UpdateCustomerInBillingPlatformJob])

      assert_enqueued_jobs(0, only: Billing::UpdateCustomerInBillingPlatformJob) do
        plan_sub = create(:billing_sales_serve_plan_subscription, customer: @business.customer)
      end

      assert_dogstats_increment(0, "plan_subscription.billing_platform_update_customer_called")
    end

    test "enqueues sync job on creation of plan" do
      enable_feature_flag(:sync_billing_platform_customers_on_subscription_changes)
      @business.customer.update!(billed_via_billing_platform: true)

      # Process any enqueued jobs
      perform_enqueued_jobs(only: [Billing::UpdateCustomerInBillingPlatformJob])

      assert_enqueued_jobs(1, only: Billing::UpdateCustomerInBillingPlatformJob) do
        plan_sub = create(:billing_sales_serve_plan_subscription, customer: @business.customer)

        assert_enqueued_with(job: Billing::UpdateCustomerInBillingPlatformJob, args: [@business.customer.reload])
      end

      # Synchronization enqueued
      assert_dogstats_increment(1, "plan_subscription.billing_platform_update_customer_called", tags: ["sales_managed:true"])
    end

    test "enqueues sync job on update of plan" do
      enable_feature_flag(:sync_billing_platform_customers_on_subscription_changes)
      @business.customer.update!(billed_via_billing_platform: true)
      plan_sub = create(:billing_sales_serve_plan_subscription, customer: @business.customer)

      # Process any enqueued jobs
      perform_enqueued_jobs(only: [Billing::UpdateCustomerInBillingPlatformJob])

      assert_enqueued_jobs(1, only: Billing::UpdateCustomerInBillingPlatformJob) do
        plan_sub.update(billing_start_date: GitHub::Billing.today - 5.days)

        assert_enqueued_with(job: Billing::UpdateCustomerInBillingPlatformJob, args: [@business.customer.reload])
      end

      # Synchronization enqueued
      assert_dogstats_increment(2, "plan_subscription.billing_platform_update_customer_called", tags: ["sales_managed:true"])
    end

    test "enqueues sync job on deletion of plan" do
      enable_feature_flag(:sync_billing_platform_customers_on_subscription_changes)
      @business.customer.update!(billed_via_billing_platform: true)
      plan_sub = create(:billing_sales_serve_plan_subscription, customer: @business.customer)

      # Process any enqueued jobs
      perform_enqueued_jobs(only: [Billing::UpdateCustomerInBillingPlatformJob])

      assert_enqueued_jobs(1, only: Billing::UpdateCustomerInBillingPlatformJob) do
        plan_sub.destroy

        assert_enqueued_with(job: Billing::UpdateCustomerInBillingPlatformJob, args: [@business.customer.reload])
      end

      # Synchronization enqueued
      assert_dogstats_increment(2, "plan_subscription.billing_platform_update_customer_called", tags: ["sales_managed:true"])
    end
  end
end if GitHub.billing_enabled?
