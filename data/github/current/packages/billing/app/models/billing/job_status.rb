# typed: strict
# frozen_string_literal: true

module Billing
  class JobStatus < ::JobStatus
    include ::JobStatus::Context

    SYNCHRONOUS_PAYMENT_COLLECTION_JOB_STATUS_PREFIX = "synchronous_payment_collection"

    # Normally we would use this in handle_id? to check if a job matches
    # a tracked jobs prefix, but we have a special case where the JobStatus
    # is actually being created in BillingSettingsHelper#synchronous_payment_collection_job_status
    # and passed to the jobs. I'm leaving this here because it does still
    # provide a list of the jobs related to this JobStatus.
    sig { returns(T::Array[T.untyped]) }
    def self.tracked_jobs
      [
        ChangeSubscription,
        ::CollectPaymentForUpgradeJob,
        PlanChange::PerSeatPricingModel
      ].freeze
    end

    sig { params(id: String).returns(T::Boolean) }
    def self.handles_id?(id)
      id.start_with?(SYNCHRONOUS_PAYMENT_COLLECTION_JOB_STATUS_PREFIX)
    end

    sig { returns(GitHub::KV) }
    def self.kv_store
      Billing::Kv.store
    end
  end
end
