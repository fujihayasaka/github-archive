# typed: strict
# frozen_string_literal: true

require "test_helper"

class Billing::OnboardCohortIn7DaysAdminAlertJobTest < ActiveJob::TestCase
  include GitHub::FeatureFlagTestHelper

  setup do
    travel_to "2024-12-12 11:00:00"

    create_list(:billing_platform_enabled_product, 5, planned_migration_date: 5.days.from_now, migration_date: nil)
    create_list(:billing_platform_enabled_product, 6, planned_migration_date: 6.days.from_now, migration_date: nil)
    create_list(:billing_platform_enabled_product, 7, planned_migration_date: 7.days.from_now, migration_date: nil)
    create_list(:billing_platform_enabled_product, 8, planned_migration_date: 8.days.from_now, migration_date: nil)

    enable_feature_flag(:billing_onboard_billing_platform_cohort_in_7_days_admin_alert_job_enabled)
  end

  test "we notify slack how many customers will be onboarded in 7 days" do
    GitHub::Chatterbox.client.expects(:say!).with(
      "#vnext-migrations",
      "Onboarding 7 customers to Billing Platform on 2024-12-19"
    ).once

    Billing::OnboardCohortIn7DaysAdminAlertJob.perform_now
  end

  test "we don't notify if no customers are being onboarded in 7 days from today" do
    travel_to "2024-12-24"

    GitHub::Chatterbox.client.expects(:say!).never

    Billing::OnboardCohortIn7DaysAdminAlertJob.perform_now
  end
end if GitHub.billing_enabled?
