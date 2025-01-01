# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: strict
# frozen_string_literal: true

module Billing
  module Migration
    class BillingPlatformMigrationSchedulerJob < BillingJob
      schedule interval: 1.day, condition: -> { GitHub.billing_enabled? }

      locked_by timeout: 30.minutes, key: ActiveJob::LockingJob::DEFAULT_LOCK_PROC

      retry_on StandardError
      retry_on_dirty_exit
      retry_on_recoverable_exceptions

      exempt_from_tenant_context_requirement

      sig { void }
      def perform
        record_timing("billing_platform_migration_scheduler_job.total_time") do
          notify_customers_of_upcoming_migration
        end
      end

      private

      sig { void }
      def notify_customers_of_upcoming_migration
        record_timing("billing_platform_migration_scheduler_job.email_time") do
          BillingPlatformEnabledProduct.where(migration_date: nil)
            .where.not(planned_migration_date: nil)
            .where(planned_migration_date: Time.now.beginning_of_day..30.days.from_now.end_of_day)
            .where(email_sent_at: nil)
            .find_each do |config|
              updated = BillingPlatformEnabledProduct.throttle_writes { config.update(email_sent_at: Time.now) }
              BillingNotificationsMailer.billing_platform_planned_migration_notice(config).deliver_later if updated
              report_metrics(config, updated)
            end
        end
      end

      sig { params(config: BillingPlatformEnabledProduct, notified: T::Boolean).void }
      def report_metrics(config, notified)
        GitHub.dogstats.increment("billing_platform_migration_scheduler_job.email_sent", tags: ["notified:#{notified}"])
        GitHub.logger.info(
          "Billing platform planned migration notice",
          "gh.billing_platform_enabled_product.id": config.id,
          "gh.customer.id": config.customer_id,
          "code.completion.notified": notified,
        )
      end

      sig { params(name: String, block: T.proc.returns(T.untyped)).void }
      def record_timing(name, &block)
        start = Time.now
        yield
        GitHub.dogstats.timing_since(name, start)
      end
    end
  end
end
