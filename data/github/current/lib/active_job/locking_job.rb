# typed: false
# frozen_string_literal: true

require "sorbet-runtime"

module ActiveJob
  module LockingJob
    extend ActiveSupport::Concern
    extend T::Helpers

    DEFAULT_LOCK_TIMEOUT = 60 * 60 # 1 hour
    DEFAULT_LOCK_KEY = "key"
    RETRY_ON_PERFORM_TIME_LOCK_EXCEPTION_FLAG = :retry_on_perform_time_lock_exception

    # Raised when lock acquisition fails at perform time due to an infrastructure
    # error (e.g. Redis unavailable). Caught by retry_on in ApplicationJob so
    # the job is retried with back-off instead of failing permanently.
    class PerformTimeLockError < StandardError; end

    # Lock jobs by unique arguments by default.
    DEFAULT_LOCK_PROC = proc do |job|
      if job.arguments.empty?
        DEFAULT_LOCK_KEY
      else
        DEFAULT_LOCK_STRINGIFY_PROC.call(job.arguments)
      end
    end

    # Predictably stringify job arguments, including AR models.
    DEFAULT_LOCK_STRINGIFY_PROC = proc do |args|
      args.map do |obj|
        case obj
        when ApplicationRecord::Base
          "#{obj.class.name}#{obj.id}"
        when Hash
          transformed = obj.transform_values do |value|
            DEFAULT_LOCK_STRINGIFY_PROC.call([value])
          end
          sorted = transformed.to_a.sort_by { |x| x.first.to_s }.join(",")
          "{#{sorted}}"
        when Array
          "[#{obj.map { |o| DEFAULT_LOCK_STRINGIFY_PROC.call([o]) }.join(",")}]"
        else
          obj.to_s
        end
      end.join(" ")
    end

    included do
      # Retry when perform-time lock acquisition fails (e.g. Redis unavailable).
      # The job will be retried with polynomial back-off, giving Redis time to
      # recover before the next attempt.
      retry_on PerformTimeLockError, wait: :polynomially_longer, attempts: 5

      attr_writer :lock_key
      attr_writer :enqueue_lock_acquired

      class_attribute :_lock_key, instance_accessor: false
      class_attribute :_lock_timeout, instance_accessor: false

      around_enqueue do |job, block|
        if job.locking?
          dd_tags = job.locking_dd_tags(phase: "enqueue")
          GitHub.dogstats.increment("jobs.locking.enqueue", tags: dd_tags)

          # Skip enqueue-time lock acquisition when the job is being retried
          # after a PerformTimeLockError. Retrying re-enqueues the job, which
          # would attempt a Redis call that is likely to fail again (e.g. Redis
          # is down). Skipping here halves the number of failed Redis calls per
          # retry cycle — the lock will be acquired at perform time instead.
          if job.perform_time_lock_attempt >= 2
            block.call
            next
          end

          # Try to acquire the lock at enqueue time to reduce duplicate enqueues.
          begin
            acquired = job.acquire_lock
            acquire_tags = dd_tags + (acquired ? ["lock_acquired:true"] : ["lock_acquired:false"])
            GitHub.dogstats.increment("jobs.locking.acquire_lock", tags: acquire_tags)
            unless acquired
              GlobalInstrumenter.instrument("jobs.lock-not-acquired", { job: job })
              next
            end
            job.enqueue_lock_acquired = true
          rescue => error
            error_tags = dd_tags + ["lock_acquired:error", "error:#{error.class}"]
            error_tags += error.cause ? ["error_cause:#{error.cause.class}"] : []
            GitHub.dogstats.increment("jobs.locking.acquire_lock", tags: error_tags)
            Failbot.report(error, app: "job-locking", job_class: job.class.name)

            # Fall through and enqueue despite the error — the lock will be
            # acquired authoritatively at perform time.
          end
        end

        block.call
      end

      around_perform do |job, block|
        unless job.locking?
          block.call
          next
        end

        enqueue_lock_acquired = job.enqueue_lock_acquired?
        has_enqueued_at = job.enqueued_at.present?
        dd_tags = job.locking_dd_tags(phase: "perform")
        dd_tags += ["has_enqueued_at:#{has_enqueued_at}"]
        GitHub.dogstats.increment("jobs.locking.perform", tags: dd_tags + ["enqueue_lock_acquired:#{enqueue_lock_acquired}"])

        # Attempt perform-time lock acquisition when the lock was not already
        # acquired at enqueue time and the job has an enqueued_at timestamp.
        # This covers:
        # 1. Jobs from perform_later where enqueue-time acquisition failed.
        # 2. Jobs from perform_all_later which bypass around_enqueue entirely.
        #
        # Jobs from perform_now are NOT covered since they don't have an
        # enqueued_at timestamp.
        if !enqueue_lock_acquired && has_enqueued_at
          begin
            acquired = job.acquire_lock
            acquire_tags = dd_tags + ["lock_acquired:#{acquired}"]
            GitHub.dogstats.increment("jobs.locking.acquire_lock", tags: acquire_tags)
            unless acquired
              GlobalInstrumenter.instrument("jobs.lock-not-acquired", { job: job })
              next
            end
          rescue => error
            retry_on_exception = job.retry_on_perform_time_lock_exception?
            error_tags = dd_tags + ["lock_acquired:error", "error:#{error.class}", "retry_on_exception:#{retry_on_exception}"]
            error_tags += error.cause ? ["error_cause:#{error.cause.class}"] : []
            GitHub.dogstats.increment("jobs.locking.acquire_lock", tags: error_tags)
            Failbot.report(error, app: "job-locking", job_class: job.class.name)

            # Feature flag for disabling retries on perform-time lock acquisition errors in case
            # of unexpected problems, e.g. too long retrying causing unacceptable load on Aqueduct
            # due to too many jobs in the system.
            if retry_on_exception
              raise PerformTimeLockError, "Exception while acquiring lock at perform time: #{error.message}"
            else
              raise
            end
          end
        end

        begin
          block.call
          job_succeeded = true
        rescue StandardError, Aqueduct::Worker::JobKilled => exception
          job_succeeded = false
          raise exception
        ensure
          clear_lock_after_job(dd_tags: dd_tags, job_succeeded: job_succeeded)
        end
      end
    end

    module ClassMethods
      def lock_key
        self._lock_key
      end

      # The name of the "lock set" where the key derived from arguments will be
      # set to implement locking.  Defaults to the name of the class.
      def lock_set_name
        self.name
      end

      def lock_timeout
        self._lock_timeout.to_i
      end

      def locked_by(key:, timeout:)
        self._lock_key = key
        self._lock_timeout = timeout
      end
    end
    mixes_in_class_methods(ClassMethods)

    def serialize
      super.tap do |obj|
        obj["lock_key"] = lock_key
        obj["enqueue_lock_acquired"] = @enqueue_lock_acquired
      end
    end

    def deserialize(job_data)
      super(job_data)
      self.lock_key = job_data["lock_key"]
      self.enqueue_lock_acquired = job_data["enqueue_lock_acquired"]
    end

    def lock_key
      return nil unless self.class.lock_timeout > 0 && self.class.lock_key.present?
      @lock_key ||= begin
        key = self.class.lock_key.call(self)
        key = DEFAULT_LOCK_STRINGIFY_PROC.call([key]) unless key.is_a?(String)
        key
      end
    end

    def safe_lock_key
      return nil unless lock_key.present?
      @safe_lock_key ||= Digest::SHA256.hexdigest(lock_key)
    end

    def locking?
      lock_key.present?
    end

    delegate :acquire_lock, :clear_lock, :locked?, to: :hash_lock

    def enqueue_lock_acquired?
      !!@enqueue_lock_acquired
    end

    def retry_on_perform_time_lock_exception?
      FeatureFlag.vexi.enabled?(RETRY_ON_PERFORM_TIME_LOCK_EXCEPTION_FLAG, job_class_actor, default: true)
    end

    # Returns the 1-based attempt number for PerformTimeLockError retries.
    # Reads from exception_executions (populated by executions_for in retry_on)
    # which tracks per-exception retry counts. At the point this is called
    # (before raising PerformTimeLockError), the counter reflects previous
    # retries, so we add 1 for the current attempt.
    def perform_time_lock_attempt
      key = [PerformTimeLockError].to_s
      (exception_executions&.dig(key) || 0) + 1
    end

    def locking_dd_tags(phase:)
      phase_tag = "phase:#{phase}"
      tags = hash_lock.dd_tags + [phase_tag]
      tags << "perform_time_lock_attempt:#{perform_time_lock_attempt}"
      tags
    end

    private

    def clear_lock_after_job(dd_tags:, job_succeeded:)
      clear_lock
    rescue => clear_error
      report_clear_lock_error(error: clear_error, dd_tags: dd_tags, job_succeeded: job_succeeded, clear_lock_attempt: "initial")
      retry_clear_lock(dd_tags: dd_tags, job_succeeded: job_succeeded)
    end

    def retry_clear_lock(dd_tags:, job_succeeded:)
      clear_lock
    rescue => clear_error
      report_clear_lock_error(error: clear_error, dd_tags: dd_tags, job_succeeded: job_succeeded, clear_lock_attempt: "retry")
    end

    def report_clear_lock_error(error:, dd_tags:, job_succeeded:, clear_lock_attempt:)
      error_tags = dd_tags + ["error:#{error.class}", "job_succeeded:#{job_succeeded}", "clear_lock_attempt:#{clear_lock_attempt}"]
      error_tags += error.cause ? ["error_cause:#{error.cause.class}"] : []
      GitHub.dogstats.increment("jobs.locking.clear_lock_error", tags: error_tags)
      Failbot.report(error, app: "job-locking", job_class: self.class.name) if clear_lock_attempt == "retry"
    end

    def hash_lock
      @hash_lock ||= JobHashLock.new(self)
    end
  end
end
