# typed: strict
# frozen_string_literal: true

module Billing
  class OnboardBillingPlatformCohortByDateKickoffJob < BillingJob
    include ActionView::Helpers::TextHelper
    include ActionView::Helpers::NumberHelper

    retry_on_dirty_exit
    retry_on_recoverable_exceptions

    queue_as :billing_platform_onboard_customer

    sig { void }
    def perform
      return unless GitHub.billing_enabled?
      return unless FeatureFlag.vexi.enabled_or_raise?(:billing_onboard_billing_platform_cohort_cohort_by_date_kickoff_job) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage

      ready_for_migration = BillingPlatformEnabledProduct.not_migrated.with_planned_migration_date(GitHub::Billing.today)

      GitHub::Chatterbox.client.say!("#vnext-migrations", "[#{GitHub::Billing.today}] Onboarding #{number_with_delimiter(ready_for_migration.count)} #{"customer".pluralize(ready_for_migration.count)} to Billing Platform today")

      with_write do
        ready_for_migration.find_each do |member|
          next if member.customer.nil?

          T.must(member.customer).onboard_to_all_billing_platform_products
        end
      end
    end
  end
end
