# typed: true
# frozen_string_literal: true

class UpdateNotificationSummaryWithLocksJob < UpdateNotificationSummaryJob
  queue_as :kubernetes_notifications

  RETRYABLE_ERRORS = [
    GitHub::Restraint::UnableToLock,
    Redis::CommandError,
    Redis::ConnectionError,
    Redis::CannotConnectError,
    Redis::TimeoutError,
  ].freeze

  retry_on_dirty_exit
  retry_on UpdateNotificationSummaryJob::UpdateNotificationSummaryError, wait: :polynomially_longer, attempts: 20
  retry_on *RETRYABLE_ERRORS, wait: :polynomially_longer, attempts: 20

  # 2 minutes is picked as atribtrary timeout, feel free to update it if needed
  LOCK_TTL = 2.minutes

  ### Locking
  # This job has a customized locking logic that guarantees the following:
  # - Only one job can get enqueued for the same klass for same id at a time
  # - Only one job gets peformed for the same klass for same id at a time
  # - The job is performed at least once AFTER someone tried to enqueue it
  # The later requirement differs from the standard locking implemented in
  # the ActiveJob::LockingJob module. To achieve the desired behavior we are
  # using two locks: one for the queue and one for performing the job. As soon
  # as we enqueue a job we lock the queue and as soon as we start performing a job
  # we release the queue lock and acquire the lock for performing the job:
  #
  # Queue lock | Perform lock | Effect
  #            |              | new job can get enqueued, a job can get performed
  #     x      |              | no job can get enueued, job on the queue can get performed
  #            |      x       | new job can get enqueued, no other job can get performed
  #     x      |      x       | no job can get enqueued, no other job can get performed

  # Override the locking? method to make sure the default locking behaviour is disabled.
  # The default locking locks a job from when it's enqueued until it's performed. We
  # want to hold the lock only until the job starts to perform.
  def locking?
    false
  end

  locked_by timeout: LOCK_TTL, key: ->(job) {
    "newsies-update-notifications-summary-enqueue-#{job.summarizable_class}-#{job.summarizable_id}"
  }

  around_enqueue do |job, block|
    if GitHub.flipper[:update_notification_summary_job_use_single_lock].enabled?
      # Only if feature flag is enabled we use only locking around perform statement
      block.call
      next
    end

    begin
      unless job.acquire_lock
        # Skip enqueueing this job if another job is holding the lock for the queue and the same klass and id
        GitHub.dogstats.increment("update_notification_summary.failed_to_acquire_enqueue_lock")
        next
      end
    rescue *RETRYABLE_ERRORS => e
      GitHub.dogstats.increment("update_notification_summary.error_enqueue_lock", tags: ["error:#{e.class.name}"])
    end

    GitHub.dogstats.increment("update_notification_summary.acquired_enqueue_lock")
    block.call
  end

  around_perform do |job, block|
    # clear the queue lock before performing the job, so a new job can get enqueued
    job.clear_lock

    # request the lock for performing the job
    lock_key = "newsies-update-notifications-summary-#{job.summarizable_class}-#{job.summarizable_id}"
    concurrent_jobs = 1
    restraint = GitHub::Restraint.new

    # restraint lock will release itself after the block is executed in ensure block
    restraint.lock!(lock_key, concurrent_jobs, LOCK_TTL) do
      tags = ["summarizable_class:#{job.summarizable_class}"]
      GitHub.dogstats.increment("update_notification_summary.acquired_perform_lock", tags: tags)
      block.call
    end
  rescue GitHub::Restraint::UnableToLock
    actor_id = job.options[:actor_id]
    GitHub.logger.info("Failed to aquire lock, retrying job to update notification summary", {
      "gh.summarizable.class": job.summarizable_class,
      "gh.summarizable.id": job.summarizable_id,
      "gh.actor.id": actor_id,
    })

    tags = ["summarizable_class:#{job.summarizable_class}"]
    GitHub.dogstats.increment("update_notification_summary.failed_to_acquire_perform_lock", tags: tags)
    raise
  rescue StandardError, ::Aqueduct::Worker::JobKilled => exception # rubocop:todo Lint/GenericRescue
    # The exception handling in the parent may trigger a re-enqueue of the
    # job so we need to make sure the lock is cleared before it runs.
    job.clear_lock
    raise exception
  end

  def summarizable_class
    if arguments[0].is_a?(Hash)
      arguments[0][:summarizable_class]
    else
      arguments[0]
    end
  end

  def summarizable_id
    if arguments[0].is_a?(Hash)
      arguments[0][:summarizable_id]
    else
      arguments[1]
    end
  end

  # Options is 5th argument if it's a hash, otherwise return an empty hash
  def options
    if arguments.size > 4 && arguments[4].is_a?(Hash)
      arguments[4]
    else
      {}
    end
  end
end
