# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class SynchronizeSalesServePlanSubscriptionJobTest < GitHub::TestCase
  include GitHub::SalesServeZuoraWebhooksTestHelper
  include JobTestHelper

  fixtures do
    @business = create(:business)
    @customer = create(:customer, business: @business)
    @sales_managed_subscription = create(:billing_sales_serve_plan_subscription, customer: @customer)
  end

  setup do
    enable_feature_flag(:queue_job_for_sales_managed_subscription_sync, @business)
    @zuora_subscription = Billing::Zuora::SalesManagedSubscription.new(
      find_subscription_response(
        id: SecureRandom.hex,
        account_id: SecureRandom.hex,
        business_id: @business.id,
        subscription_number: @sales_managed_subscription.zuora_subscription_number,
      )
    )
    @business.stubs(:sales_managed_subscription).returns(@zuora_subscription)
  end

  test "retries on dirty exit" do
    assert_retry_on_dirty_exit job: SynchronizeSalesServePlanSubscriptionJob
  end

  test "retries on recoverable exceptions" do
    assert_retry_on_recoverable_exceptions job: SynchronizeSalesServePlanSubscriptionJob
  end

  test "does not synchronize if the feature flag is disabled" do
    disable_feature_flag(:queue_job_for_sales_managed_subscription_sync)
    Billing::Zuora::SalesManagedEnterpriseSubscriptionSynchronizer.any_instance.expects(:sync).never

    SynchronizeSalesServePlanSubscriptionJob.perform_now(business: @business)
  end

  test "synchronizes the sales managed subscription" do
    Billing::Zuora::SalesManagedEnterpriseSubscriptionSynchronizer.any_instance.expects(:sync).once

    SynchronizeSalesServePlanSubscriptionJob.perform_now(business: @business)
  end

  test "synchronizes the sales managed subscription with write" do
    Billing::Zuora::SalesManagedSubscription.stubs(:fetch_by_subscription_id).returns(@zuora_subscription)

    assert_nothing_raised do
      SynchronizeSalesServePlanSubscriptionJob.perform_now(business: @business)
    end
  end

  test "does not synchronize if there is no business" do
    Billing::Zuora::SalesManagedEnterpriseSubscriptionSynchronizer.any_instance.expects(:sync).never

    SynchronizeSalesServePlanSubscriptionJob.perform_now(business: nil)

    perform_enqueued_jobs(only: SynchronizeSalesServePlanSubscriptionJob) do
      SynchronizeSalesServePlanSubscriptionJob.perform_later(business: nil)
    end
    assert_performed_jobs(1, only: SynchronizeSalesServePlanSubscriptionJob)
  end

  test "does not synchronize if there is no sales managed subscription" do
    @business.unstub(:sales_managed_subscription)

    Billing::Zuora::SalesManagedEnterpriseSubscriptionSynchronizer.any_instance.expects(:sync).never

    SynchronizeSalesServePlanSubscriptionJob.perform_now(business: @business)
  end

  test "does not synchronize if there is ghe_rate_plan_charge already" do
    @sales_managed_subscription.subscription_rate_plan_charges <<
      create(:plan_subscription_zuora_rate_plan_charge, product_rate_plan_charge_id: GitHub.zuora_sales_serve_ghe_product_charge_ids.first, payload: { effectiveStartDate: GitHub::Billing.today - 1.day, price: 100.0 })

    Billing::Zuora::SalesManagedEnterpriseSubscriptionSynchronizer.any_instance.expects(:sync).never

    SynchronizeSalesServePlanSubscriptionJob.perform_now(business: @business)
  end
end if GitHub.billing_enabled?
