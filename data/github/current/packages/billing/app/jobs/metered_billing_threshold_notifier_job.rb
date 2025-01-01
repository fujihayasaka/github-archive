# typed: true
# frozen_string_literal: true

class MeteredBillingThresholdNotifierJob < ApplicationJob
  queue_as :billing

  locked_by timeout: 5.minutes, key: DEFAULT_LOCK_PROC

  # Unable to lock means another instance of this job is already running.
  # This can be safely discarded, since this job is frequently triggered.
  discard_on GitHub::Restraint::UnableToLock

  def perform(owner_id:, product:, owner_type: "User")
    lock_key = "metered-billing-threshold-notifier-job-#{owner_type}-#{owner_id}-#{product}"
    concurrent_jobs = 1
    lock_ttl = 1.minute

    restraint = GitHub::Restraint.new
    restraint.lock!(lock_key, concurrent_jobs, lock_ttl) do
      notifier = Billing::MeteredThresholdNotifier.new(
        owner_id: owner_id,
        product: product,
        owner_type: owner_type,
      )

      if owner_type == "Business"
        notifier.notify_for_business_if_applicable
      else
        notifier.notify_if_applicable
      end
    end
  end
end
