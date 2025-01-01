# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

# Sends any newsletters that need to be run
class NewsletterDeliveryRunJob < ApplicationJob
  queue_as :newsletter_delivery_run

  exempt_from_tenant_context_requirement

  LOCK_KEY = "newsletter-delivery-run"
  MAX_JOBS = 70

  locked_by timeout: 1.hour, key: ActiveJob::LockingJob::DEFAULT_LOCK_PROC

  # Use jitter on retry to prevent all of the "failed" jobs from retrying at the same time.
  retry_on GitHub::Restraint::UnableToLock, wait: 5.minutes, jitter: 0.5
  retry_on_recoverable_exceptions
  retry_on_dirty_exit

  def perform(sub_ids)
    return unless sub_ids.present?

    restraint = GitHub::Restraint.new
    restraint.lock!(LOCK_KEY, MAX_JOBS, 1.hour) do
      GitHub.dogstats.distribution_time("newsletter.jobs.deliver_subscriptions") do
        NewsletterSubscription.deliver_subscriptions(sub_ids: sub_ids)
      end
    end
  end
end
