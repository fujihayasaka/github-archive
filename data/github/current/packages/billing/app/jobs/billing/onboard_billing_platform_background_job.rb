# typed: strict
# frozen_string_literal: true

module Billing
  class OnboardBillingPlatformBackgroundJob < BillingJob
    include ActionView::Helpers::TextHelper
    include ActionView::Helpers::NumberHelper

    retry_on_dirty_exit
    retry_on_recoverable_exceptions

    queue_as :billing_platform_onboard_customer

    sig { void }
    def perform
      return unless GitHub.billing_enabled?
      return unless GitHub.flipper[:billing_onboard_billing_platform_background_job].enabled?

      # SET LIMIT
      limit = 1

      if GitHub.flipper[:billing_onboard_billing_platform_background_job_rate_med].enabled?
        limit = 200
      end

      if GitHub.flipper[:billing_onboard_billing_platform_background_job_rate_high].enabled?
        limit = 250
      end

      cohort_name = "next_cohort"

      if GitHub.flipper[:billing_onboard_billing_platform_background_job_side_cohort].enabled?
        cohort_name = "side_cohort"
      end

      ids = Customer.in_cohort(cohort_name).not_billed_in_billing_platform.limit(limit).pluck(:id)

      GitHub.logger.info("Migrating customers on background job to billing platform", {
        "code.namespace" => "Billing::OnboardBillingPlatformBackgroundJob",
        "code.function" => "perform",
        "gh.billing.limit" => limit,
        "gh.billing.current_target" => cohort_name,
      })

      Customer.where(id: ids).find_each do |customer|
        with_write do
          customer.onboard_to_all_billing_platform_products
        end

        GitHub.logger.info("Customer migrated on background job to billing platform", {
          "code.namespace" => "Billing::OnboardBillingPlatformBackgroundJob",
          "code.function" => "perform",
          "gh.billing.limit" => limit,
          "gh.billing.current_target" => cohort_name,
          "gh.customer.id" => customer.id,
        })
        GitHub.dogstats.increment("billing.background_job_migration_total")
      end
    end
  end
end
