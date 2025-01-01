# typed: strict
# frozen_string_literal: true

module Billing
  class OnboardCohortIn7DaysAdminAlertJob < BillingJob
    include ActionView::Helpers::TextHelper
    include ActionView::Helpers::NumberHelper

    retry_on_dirty_exit
    retry_on_recoverable_exceptions

    queue_as :billing_platform_onboard_customer

    sig { void }
    def perform
      return unless GitHub.billing_enabled?
      return unless FeatureFlag.vexi.enabled_or_raise?(:billing_onboard_billing_platform_cohort_in_7_days_admin_alert_job_enabled) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage

      target_date = T.let(GitHub::Billing.today + 7.days, Date)
      customers_to_onboard = BillingPlatformEnabledProduct.not_migrated.with_planned_migration_date(target_date)

      return if customers_to_onboard.none?

      GitHub::Chatterbox.client.say!(
        "#vnext-migrations",
        "Onboarding #{number_with_delimiter(customers_to_onboard.count)} #{"customer".pluralize(customers_to_onboard.count)} to Billing Platform on #{target_date}",
      )
    end
  end
end
