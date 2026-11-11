# typed: strict
# frozen_string_literal: true

module SecurityProductsEnablement
  class CheckBillingDataIntegrityJob < ApplicationJob
    # How frequently this job is enqueued.
    JOB_INTERVAL = T.let(5.minutes, ActiveSupport::Duration)

    # How many jobs are required to check all businesses, assuming we target
    # one full scan every day.
    JOBS_PER_SCAN = T.let((1.day / JOB_INTERVAL).ceil, Integer)

    include ActiveJob::InitiallyEnqueuedAt
    include GitHub::Memoizer

    queue_as :security_products_enablement_check_billing_data_integrity

    schedule interval: JOB_INTERVAL, condition: -> { !GitHub.enterprise? }

    retry_on_dirty_exit
    retry_on_recoverable_exceptions

    exempt_from_tenant_context_requirement

    sig { void }
    def perform
      if FeatureFlag.vexi.enabled?(:clean_security_products_billing_data, default: false)
        BillingDataIntegrityChecker.clean(business_ids:)
      else
        BillingDataIntegrityChecker.check(business_ids:)
      end
    end

    private

    sig { returns(T::Array[Integer]) }
    memoize def business_ids
      ::Business
        .where("id % ? = ?", JOBS_PER_SCAN, job_number)
        .in_batches
        .each_with_object([]) do |batch, ids|
          batch_of_ids = Array.wrap(batch.where_values_hash.fetch("id"))
          ids.concat(batch_of_ids)
        end
    end

    # Returns an integer in 0...JOBS_PER_SCAN.
    sig { returns(Integer) }
    memoize def job_number
      initially_enqueued_at.getutc.seconds_since_midnight.to_i / JOB_INTERVAL
    end
  end
end
