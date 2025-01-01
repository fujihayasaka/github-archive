# typed: strict
# frozen_string_literal: true

require "test_helper"

class Billing::OnboardBillingPlatformCohortByDateKickoffJobTest < GitHub::TestCase
  setup do
    enable_feature_flag(:billing_onboard_billing_platform_cohort_cohort_by_date_kickoff_job)
  end

  test "we enqueue onboarding jobs for customers with the onboarding date of today" do
    today_customer = create(:billing_platform_enabled_product, planned_migration_date: GitHub::Billing.today)
    not_today_customer = create(:billing_platform_enabled_product, planned_migration_date: GitHub::Billing.today + 2.days)

    GitHub::Chatterbox.client.expects(:say!).with("#vnext-migrations", "[#{GitHub::Billing.today}] Onboarding 1 customer to Billing Platform today").once

    assert_enqueued_jobs(1, only: Billing::OnboardCustomerToProductInBillingPlatformJob) do
      Billing::OnboardBillingPlatformCohortByDateKickoffJob.perform_now
    end

    assert_enqueued_with(
      job: Billing::OnboardCustomerToProductInBillingPlatformJob,
      args: [
        {
          customer_id: today_customer.customer_id,
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
end if GitHub.billing_enabled?
