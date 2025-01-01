# typed: strict
# frozen_string_literal: true

require "test_helper"

class Billing::OnboardBillingPlatformBackgroundJobTest < GitHub::TestCase
  setup do
    enable_feature_flag(:billing_onboard_billing_platform_background_job)
  end

  test "no jobs enqueued if primary flag is disabled" do
    disable_feature_flag(:billing_onboard_billing_platform_background_job)
    org = create :organization, plan: GitHub::Plan.business
    customer = create :credit_card_customer
    org.customer = customer

    assert_enqueued_jobs(0, only: Billing::OnboardCustomerToProductInBillingPlatformJob) do
      Billing::OnboardBillingPlatformBackgroundJob.perform_now
    end
  end

  test "no jobs enqueued if primary flag is disabled even if other flags are enabled" do
    disable_feature_flag(:billing_onboard_billing_platform_background_job)
    enable_feature_flag(:billing_onboard_billing_platform_background_job_rate_high)
    enable_feature_flag(:billing_onboard_billing_platform_background_job_rate_med)
    org = create :organization, plan: GitHub::Plan.business
    customer = create :credit_card_customer
    org.customer = customer

    assert_enqueued_jobs(0, only: Billing::OnboardCustomerToProductInBillingPlatformJob) do
      Billing::OnboardBillingPlatformBackgroundJob.perform_now
    end
  end

  test "we enqueue onboarding jobs for customers" do
    org = create :organization, plan: GitHub::Plan.business
    customer = create :credit_card_customer
    org.customer = customer

    create(
      :billing_subscription_item,
      subscribable: create(:billing_product_uuid, :copilot, billing_cycle: :month),
      plan_subscription: create(:billing_plan_subscription, :zuora, user: org),
      quantity: 0
    )

    assert_enqueued_jobs(1, only: Billing::OnboardCustomerToProductInBillingPlatformJob) do
      Billing::OnboardBillingPlatformBackgroundJob.perform_now
    end

    assert_enqueued_with(
      job: Billing::OnboardCustomerToProductInBillingPlatformJob,
      args: [
        {
          customer_id: customer.id,
          products: [
            Billing::OnboardCustomerToProductInBillingPlatformJob::ProductEnum::Actions.serialize,
            Billing::OnboardCustomerToProductInBillingPlatformJob::ProductEnum::Codespaces.serialize,
            Billing::OnboardCustomerToProductInBillingPlatformJob::ProductEnum::Copilot.serialize,
            Billing::OnboardCustomerToProductInBillingPlatformJob::ProductEnum::Git_Lfs.serialize,
            Billing::OnboardCustomerToProductInBillingPlatformJob::ProductEnum::Packages.serialize,
          ],
          previous_customer_id: nil
        }
      ],
    )
  end

  test "we change rates with rate feature flag on" do
    enable_feature_flag(:billing_onboard_billing_platform_background_job_rate_med)
    subscribable = create(:billing_product_uuid, :copilot, billing_cycle: :month)
    org1 = create(:copilot_for_business_enabled_non_enterprise_organization)
    customer1 = create :credit_card_customer
    org1.customer = customer1

    create(
      :billing_subscription_item,
      subscribable: subscribable,
      plan_subscription: create(:billing_plan_subscription, :zuora, user: org1),
      quantity: 0
    )

    org2 = create(:copilot_for_business_enabled_non_enterprise_organization)
    customer2 = create :credit_card_customer
    org2.customer = customer2

    create(
      :billing_subscription_item,
      subscribable: subscribable,
      plan_subscription: create(:billing_plan_subscription, :zuora, user: org2),
      quantity: 0
    )

    org3 = create(:copilot_for_business_enabled_non_enterprise_organization)
    customer3 = create :credit_card_customer
    org3.customer = customer3

    create(
      :billing_subscription_item,
      subscribable: subscribable,
      plan_subscription: create(:billing_plan_subscription, :zuora, user: org3),
      quantity: 0
    )

    org4 = create(:copilot_for_business_enabled_non_enterprise_organization)
    customer4 = create :credit_card_customer
    org4.customer = customer4

    create(
      :billing_subscription_item,
      subscribable: subscribable,
      plan_subscription: create(:billing_plan_subscription, :zuora, user: org4),
      quantity: 0
    )

    org5 = create(:copilot_for_business_enabled_non_enterprise_organization)
    customer5 = create :credit_card_customer
    org5.customer = customer5

    create(
      :billing_subscription_item,
      subscribable: subscribable,
      plan_subscription: create(:billing_plan_subscription, :zuora, user: org5),
      quantity: 0
    )

    assert_enqueued_jobs(5, only: Billing::OnboardCustomerToProductInBillingPlatformJob) do
      Billing::OnboardBillingPlatformBackgroundJob.perform_now
    end

    assert_enqueued_with(
      job: Billing::OnboardCustomerToProductInBillingPlatformJob,
      args: [
        {
          customer_id: customer1.id,
          products: [
            Billing::OnboardCustomerToProductInBillingPlatformJob::ProductEnum::Actions.serialize,
            Billing::OnboardCustomerToProductInBillingPlatformJob::ProductEnum::Codespaces.serialize,
            Billing::OnboardCustomerToProductInBillingPlatformJob::ProductEnum::Copilot.serialize,
            Billing::OnboardCustomerToProductInBillingPlatformJob::ProductEnum::Git_Lfs.serialize,
            Billing::OnboardCustomerToProductInBillingPlatformJob::ProductEnum::Packages.serialize,
          ],
          previous_customer_id: nil
        }
      ],
    )

    assert_enqueued_with(
      job: Billing::OnboardCustomerToProductInBillingPlatformJob,
      args: [
        {
          customer_id: customer2.id,
          products: [
            Billing::OnboardCustomerToProductInBillingPlatformJob::ProductEnum::Actions.serialize,
            Billing::OnboardCustomerToProductInBillingPlatformJob::ProductEnum::Codespaces.serialize,
            Billing::OnboardCustomerToProductInBillingPlatformJob::ProductEnum::Copilot.serialize,
            Billing::OnboardCustomerToProductInBillingPlatformJob::ProductEnum::Git_Lfs.serialize,
            Billing::OnboardCustomerToProductInBillingPlatformJob::ProductEnum::Packages.serialize,
          ],
          previous_customer_id: nil
        }
      ],
    )

    assert_enqueued_with(
      job: Billing::OnboardCustomerToProductInBillingPlatformJob,
      args: [
        {
          customer_id: customer3.id,
          products: [
            Billing::OnboardCustomerToProductInBillingPlatformJob::ProductEnum::Actions.serialize,
            Billing::OnboardCustomerToProductInBillingPlatformJob::ProductEnum::Codespaces.serialize,
            Billing::OnboardCustomerToProductInBillingPlatformJob::ProductEnum::Copilot.serialize,
            Billing::OnboardCustomerToProductInBillingPlatformJob::ProductEnum::Git_Lfs.serialize,
            Billing::OnboardCustomerToProductInBillingPlatformJob::ProductEnum::Packages.serialize,
          ],
          previous_customer_id: nil
        }
      ],
    )

    assert_enqueued_with(
      job: Billing::OnboardCustomerToProductInBillingPlatformJob,
      args: [
        {
          customer_id: customer4.id,
          products: [
            Billing::OnboardCustomerToProductInBillingPlatformJob::ProductEnum::Actions.serialize,
            Billing::OnboardCustomerToProductInBillingPlatformJob::ProductEnum::Codespaces.serialize,
            Billing::OnboardCustomerToProductInBillingPlatformJob::ProductEnum::Copilot.serialize,
            Billing::OnboardCustomerToProductInBillingPlatformJob::ProductEnum::Git_Lfs.serialize,
            Billing::OnboardCustomerToProductInBillingPlatformJob::ProductEnum::Packages.serialize,
          ],
          previous_customer_id: nil
        }
      ],
    )

    assert_enqueued_with(
      job: Billing::OnboardCustomerToProductInBillingPlatformJob,
      args: [
        {
          customer_id: customer5.id,
          products: [
            Billing::OnboardCustomerToProductInBillingPlatformJob::ProductEnum::Actions.serialize,
            Billing::OnboardCustomerToProductInBillingPlatformJob::ProductEnum::Codespaces.serialize,
            Billing::OnboardCustomerToProductInBillingPlatformJob::ProductEnum::Copilot.serialize,
            Billing::OnboardCustomerToProductInBillingPlatformJob::ProductEnum::Git_Lfs.serialize,
            Billing::OnboardCustomerToProductInBillingPlatformJob::ProductEnum::Packages.serialize,
          ],
          previous_customer_id: nil
        }
      ],
    )
  end

  test "we enqueue onboarding jobs for customers with copilot" do
    org = create(:copilot_for_business_enabled_non_enterprise_organization)
    customer = create :credit_card_customer
    org.customer = customer

    create(
      :billing_subscription_item,
      subscribable: create(:billing_product_uuid, :copilot, billing_cycle: :month),
      plan_subscription: create(:billing_plan_subscription, :zuora, user: org),
      quantity: 0
    )

    assert_enqueued_jobs(1, only: Billing::OnboardCustomerToProductInBillingPlatformJob) do
      Billing::OnboardBillingPlatformBackgroundJob.perform_now
    end

    assert_enqueued_with(
      job: Billing::OnboardCustomerToProductInBillingPlatformJob,
      args: [
        {
          customer_id: customer.id,
          products: [
            Billing::OnboardCustomerToProductInBillingPlatformJob::ProductEnum::Actions.serialize,
            Billing::OnboardCustomerToProductInBillingPlatformJob::ProductEnum::Codespaces.serialize,
            Billing::OnboardCustomerToProductInBillingPlatformJob::ProductEnum::Copilot.serialize,
            Billing::OnboardCustomerToProductInBillingPlatformJob::ProductEnum::Git_Lfs.serialize,
            Billing::OnboardCustomerToProductInBillingPlatformJob::ProductEnum::Packages.serialize,
          ],
          previous_customer_id: nil
        }
      ],
    )
  end

  test "we don't enqueue onboarding jobs for customers in a migration cohort" do
    org = create :organization, plan: GitHub::Plan.business
    customer = create :credit_card_customer
    org.customer = customer
    migration_date = 3.days.ago
    create(:billing_platform_enabled_product, customer: customer, planned_migration_date: GitHub::Billing.today + 2.days)

    assert_enqueued_jobs(0, only: Billing::OnboardCustomerToProductInBillingPlatformJob) do
      Billing::OnboardBillingPlatformBackgroundJob.perform_now
    end
  end
end if GitHub.billing_enabled?
