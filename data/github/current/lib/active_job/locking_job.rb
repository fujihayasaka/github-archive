# typed: false
# frozen_string_literal: true

require "sorbet-runtime"

module ActiveJob
  module LockingJob
    extend ActiveSupport::Concern
    extend T::Helpers

    DEFAULT_LOCK_TIMEOUT = 60 * 60 # 1 hour
    DEFAULT_LOCK_KEY = "key"
    PERFORM_TIME_LOCKING_FLAG = :job_locking_at_perform_time
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
      attr_writer :perform_time_locking

      class_attribute :_lock_key, instance_accessor: false
      class_attribute :_lock_timeout, instance_accessor: false

      around_enqueue do |job, block|
        if job.locking?
          perform_time_locking = job.perform_time_locking?
          dd_tags = job.locking_dd_tags(phase: "enqueue", perform_time_locking: perform_time_locking)
          GitHub.dogstats.increment("jobs.locking.enqueue", tags: dd_tags)

          # Snapshot the flag value so around_perform uses the same decision
          # even if the flag is toggled between enqueue and perform.
          job.perform_time_locking = perform_time_locking

          # Try to acquire the lock.
          # This is the standard behavior in enqueue-time locking.
          # For perform-time locking, this reduces duplicate enqueues.
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
            Failbot.report(error, app: "job-hash-lock", job_class: job.class.name)

            # For perform time locking, we fall through and enqueue despite the error
            # and the lock will be acquired authoritatively at perform time.
            # For enqueue time locking, we want to fail and not enqueue if we couldn't
            # acquire the lock due to an error, since that is the main point of the lock.
            raise if !perform_time_locking
          end
        end

        block.call
      end

      around_perform do |job, block|
        unless job.locking?
          block.call
          next
        end

        enqueued_with_perform_time_locking = job.enqueued_with_perform_time_locking?
        dd_tags = job.locking_dd_tags(phase: "perform", perform_time_locking: enqueued_with_perform_time_locking)
        GitHub.dogstats.increment("jobs.locking.perform", tags: dd_tags + ["enqueue_lock_acquired:#{job.enqueue_lock_acquired?}"])

        if enqueued_with_perform_time_locking
          # This job went through around_enqueue with the flag enabled.
          # Use the stored flag value (enqueued_with_perform_time_locking?) rather
          # than re-checking the live flag, so that the enqueue/perform
          # decision is always consistent even if the flag is toggled.
          # If enqueue_lock_acquired? is true, we already own the lock — skip
          # the Redis call entirely. Otherwise, try to acquire the lock now
          # (covers the case where enqueue-time acquisition was skipped due to
          # a Redis error).
          if job.enqueue_lock_acquired?
            GitHub.dogstats.increment("jobs.locking.perform_time_already_owned", tags: dd_tags)
          else
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
              Failbot.report(error, app: "job-hash-lock", job_class: job.class.name)

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
        end

        begin
          block.call
          job.clear_lock
        rescue StandardError, Aqueduct::Worker::JobKilled => exception # rubocop:todo Lint/RescueException
          # The exception handling in the parent may trigger a re-enqueue of the
          # job so we need to make sure the lock is cleared before it runs.
          begin
            job.clear_lock
          rescue => clear_error
            error_tags = dd_tags + ["error:#{clear_error.class}"]
            error_tags += clear_error.cause ? ["error_cause:#{clear_error.cause.class}"] : []
            GitHub.dogstats.increment("jobs.locking.clear_lock_error", tags: error_tags)
            Failbot.report(clear_error, app: "job-hash-lock", job_class: job.class.name)
          end
          raise exception
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
        obj["perform_time_locking"] = @perform_time_locking
      end
    end

    def deserialize(job_data)
      super(job_data)
      self.lock_key = job_data["lock_key"]
      self.enqueue_lock_acquired = job_data["enqueue_lock_acquired"]
      self.perform_time_locking = job_data["perform_time_locking"]
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

    # Whether the perform-time locking flag was enabled when this job was
    # enqueued. Stored at enqueue time so the decision is consistent even
    # if the flag is toggled before the job is performed.
    def enqueued_with_perform_time_locking?
      !!@perform_time_locking
    end

    def perform_time_locking?
      FeatureFlag.vexi.enabled?(PERFORM_TIME_LOCKING_FLAG, job_class_actor, default: false)
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

    def locking_dd_tags(phase:, perform_time_locking:)
      lock_strategy_tag = perform_time_locking ? "lock_strategy:perform_time" : "lock_strategy:enqueue_time"
      phase_tag = "phase:#{phase}"
      tags = hash_lock.dd_tags + [lock_strategy_tag, phase_tag]
      tags << "perform_time_lock_attempt:#{perform_time_lock_attempt}" if perform_time_locking
      tags
    end

    private

    def hash_lock
      @hash_lock ||= JobHashLock.new(self)
    end
  end
end
