# typed: true
# frozen_string_literal: true

class WindbeamDeletionRequestJob < ApplicationJob
  queue_as :windbeam_deletion_request

  locked_by timeout: ActiveJob::LockingJob::DEFAULT_LOCK_TIMEOUT, key: ->(job) { job.arguments.first }

  MAX_RETRIES = 5

  RETRYABLE_ERRORS = [
    WindbeamApi::Errors::CommunicationError,
    Faraday::TimeoutError,
    Faraday::ConnectionFailed,
  ].freeze

  RETRYABLE_ERRORS.each do |error_class|
    retry_on error_class, wait: :polynomially_longer, attempts: MAX_RETRIES do |job, error|
      job.send(:fall_back_to_legacy_delete, error)
    end
  end

  retry_on_recoverable_exceptions attempts: MAX_RETRIES
  retry_on_dirty_exit

  def perform(user_id, _login)
    user = User.find_by(id: user_id)
    return false unless user&.deleted?

    Dsr.delete_user(user)
  end

  def fall_back_to_legacy_delete(error)
    user_id = arguments.first

    GitHub.logger.error("Windbeam deletion request failed after retries for user #{user_id}: #{error.message}")
    Failbot.report(error, user_id: user_id, context: "windbeam_deletion_retries_exhausted")

    user = User.find_by(id: user_id)
    return unless user&.deleted?

    UserDeleteJob.perform_later(user.id, user.display_login)
  end
end
