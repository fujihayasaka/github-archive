# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class TwoFactorRecoveryRequestCleanupJob < ApplicationJob
  queue_as :two_factor_recovery

  # This job is stateless and should be retried if a worker is killed.
  retry_on_dirty_exit

  # Amount of time to wait before sending Zendesk ticket for verification
  # This is a default time decided upon by the authentication team
  # to prevent account takeovers
  EXPIRY_TIME = 2.weeks

  # To ensure we don't process an unbounded number of recovery requests we only
  # process at most 1000 per job run. In the unlikely event that we have more
  # than 1000 they will get processed the next time the job runs.
  BATCH_LIMIT = 1_000
  BATCH_SIZE = 100

  rescue_from(ActiveJob::DeserializationError) do |e|
    # Failing to find the record to be cleaned-up is not an error
    true if e.cause.is_a?(ActiveRecord::RecordNotFound) && e.cause.model == "TwoFactorRecoveryRequest"
  end

  before_enqueue do |job|
    # Create a JobStatus for the job being enqueued.
    if job.arguments.first
      request = job.arguments.first[:request]
      ActiveRecord::Base.connected_to(role: :writing) do
        GitHub::Authentication::JobStatus.create(id: TwoFactorRecoveryRequestCleanupJob.job_id(request.id))
      end
    end
  end

  def self.prefix
    "two_factor_recovery_cleanup"
  end

  def self.job_id(request_id)
    "#{prefix}_#{request_id}"
  end

  def self.status(request_id)
    GitHub::Authentication::JobStatus.find(TwoFactorRecoveryRequestCleanupJob.job_id(request_id))
  end

  schedule interval: 1.hour, condition: -> { !GitHub.enterprise? }

  def perform(request: nil)
    if request.present?
      ActiveRecord::Base.connected_to(role: :writing) do
        request.destroy!
      end
      return
    end

    expired_request_ids = TwoFactorRecoveryRequest.where(
      ["updated_at <= ?", EXPIRY_TIME.ago]
    ).limit(BATCH_LIMIT).pluck(:id)

    expired_token_request_ids = TwoFactorRecoveryRequest.where(
      [
        "reviewer_id IS NOT NULL and approved_at <= ?",
        TwoFactorRecoveryRequest::COMPLETE_TOKEN_EXPIRY.ago
      ]
    ).limit(BATCH_LIMIT).pluck(:id)

    recovery_request_ids =
      (expired_request_ids + expired_token_request_ids).uniq
    # Avoid collisions with other requests that are queued for deletion
    ActiveRecord::Base.connected_to(role: :writing) do
      recovery_request_ids.delete_if { |id| TwoFactorRecoveryRequestCleanupJob.status(id).present? }
      recovery_request_ids.each_slice(BATCH_SIZE) do |ids|
        TwoFactorRecoveryRequest.destroy(ids)
      end
    end
  end
end
