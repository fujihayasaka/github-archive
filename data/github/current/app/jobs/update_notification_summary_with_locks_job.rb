# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class UpdateNotificationSummaryWithLocksJob < ApplicationJob
  include GitHub::Tracing
  trace_method :build_summarizable

  queue_as :kubernetes_notifications

  RETRYABLE_ERRORS = [
    GitHub::Restraint::UnableToLock,
    Redis::CommandError,
    Redis::ConnectionError,
    Redis::CannotConnectError,
    Redis::TimeoutError,
  ].freeze

  class UpdateNotificationSummaryError < StandardError; end

  retry_on_dirty_exit
  retry_on UpdateNotificationSummaryError, wait: :polynomially_longer, attempts: 20
  retry_on *RETRYABLE_ERRORS, wait: :polynomially_longer, attempts: 20

  resolve_tenant_context do |klass, id|
    subject = klass.constantize.find_by(id: id) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
    Notifications::TenantContext.resolve_tenant(subject&.notifications_list)
  rescue NameError
    nil
  end

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

  def perform(summarizable_class, summarizable_id, enqueue = false, retryable = false, options = {})
    begin
      status = :error
      status = update(summarizable_class, summarizable_id, options)
    ensure
      GitHub.logger.info(
        "code.namespace" => self.class.name,
        "code.function" => "perform",
        "gh.notifyd.subject.type" => summarizable_class,
        "gh.notifyd.subject.id" => summarizable_id,
        "gh.notifyd.status" => status.to_s
      )
      GitHub.dogstats.increment("update_notification_summary.perform.count", tags: ["subject:#{summarizable_class}", "status:#{status}"])
    end
  end

  def update(summarizable_class, summarizable_id, options)
    options = options.with_indifferent_access

    summarizable = build_summarizable(summarizable_class, summarizable_id)
    return :no_subject unless summarizable

    succeeded = GitHub.tracer.in_span("update_notification_summary_now", kind: :internal, attributes: { "code.namespace" => summarizable_class }) do
      with_write do
        NotificationSummary.throttle do
          summarizable.update_notification_summary_now
        end
      end
    end

    raise UpdateNotificationSummaryError unless succeeded
    :success
  end

  def build_summarizable(summarizable_class, summarizable_id)
    summarizable_class = begin
      summarizable_class.constantize
    rescue NameError
      return
    end
    summarizable_class.find_by_id(summarizable_id) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
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
