# typed: true
# frozen_string_literal: true

class UserDeleteJob < ApplicationJob
  queue_as :user_delete

  locked_by timeout: ActiveJob::LockingJob::DEFAULT_LOCK_TIMEOUT, key: ->(job) { job.arguments.first }

  class DisallowedUserDeletionError < StandardError; end

  # Max number of attempts for all retryable failures
  MAX_ATTEMPTS = 20

  # Retry on timeouts and connection errors.
  RETRYABLE_ERRORS = [
    Errno::ETIMEDOUT,
    Redis::TimeoutError, # Raised when performing I/O times out
  ].freeze

  # Declare a separate `retry_on` for each error so their counts don't stack
  RETRYABLE_ERRORS.each do |error_class|
    retry_on error_class, wait: :polynomially_longer, attempts: MAX_ATTEMPTS do |_job, error|
      # No need for extra details here as they get pushed to the log context during `perform`
      GitHub.logger.error("exception.message": error.message, "exception.type": error.class.name)
      raise error
    end
  end

  # retry on worker shutdown, common db exceptions, and
  # throttler errors.
  retry_on_recoverable_exceptions attempts: MAX_ATTEMPTS
  retry_on_dirty_exit

  # if the record doesn't exist we assume the work has been
  # completed.
  discard_on ActiveRecord::RecordNotFound

  def self.job_id(user_id)
    "user-delete-job_#{user_id}"
  end

  # Gets the status for a given job
  def self.status(user_id)
    JobStatus.find(job_id(user_id))
  end

  # Public: Destroys a particular user. This cleans up user data in the background after
  # it's been requested that the user is deleted.
  #
  # user_id - Id of the user to destroy
  # login   - Login of the user to destroy
  def perform(user_id, login)
    user = User.find_by(id: user_id)
    return false unless user

    if user.never_deletable?
      raise DisallowedUserDeletionError, "attempted to delete never deletable user #{login} (#{user_id})"
    end

    begin
      Dsr.delete_user(user)
    rescue StandardError => e
      GitHub.logger.error(e)
      Failbot.report(e)
    end

    status = JobStatus.create(id: self.class.job_id(user_id))
    status.track do
      Failbot.push(user_id: user_id)

      # don't wrap remove! in transactions because it's full of database throttling
      with_write do
        user.remove!
      end
    end
  end
end
