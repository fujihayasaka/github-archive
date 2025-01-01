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
        limit = 60
      end

      if GitHub.flipper[:billing_onboard_billing_platform_background_job_rate_high].enabled?
        limit = 100
      end

      products = [
        Billing::OnboardCustomerToProductInBillingPlatformJob::ProductEnum::Actions.serialize,
        Billing::OnboardCustomerToProductInBillingPlatformJob::ProductEnum::Codespaces.serialize,
        Billing::OnboardCustomerToProductInBillingPlatformJob::ProductEnum::Copilot.serialize,
        Billing::OnboardCustomerToProductInBillingPlatformJob::ProductEnum::Git_Lfs.serialize,
        Billing::OnboardCustomerToProductInBillingPlatformJob::ProductEnum::Packages.serialize,
      ]

      current_target = "copilot_pro_business"
      ids = Customer.with_copilot_subscription.not_billed_in_billing_platform.limit(limit).pluck(:id)

      GitHub.logger.info("Migrating customers on background job to billing platform", {
        "code.namespace" => "Billing::OnboardBillingPlatformBackgroundJob",
        "code.function" => "perform",
        "gh.billing.limit" => limit,
        "gh.billing.current_target" => current_target,
      })

      Customer.where(id: ids).find_each do |customer|
        with_write do
          customer.onboard_to_billing_platform(
            products: products
          )
        end

        GitHub.logger.info("Customer migrated on background job to billing platform", {
          "code.namespace" => "Billing::OnboardBillingPlatformBackgroundJob",
          "code.function" => "perform",
          "gh.billing.limit" => limit,
          "gh.billing.current_target" => current_target,
          "gh.customer.id" => customer.id,
        })
        GitHub.dogstats.increment("billing.background_job_migration_total")
      end
    end
  end
end
