# typed: false
# frozen_string_literal: true

require "sorbet-runtime"

# Implements a pattern of job concurrency control by acquiring separate locks during
# job enqueue and perform. This allows for a single job to be enqueued while another is running,
# to ensure that any changes to underlying data sources which may occur during the job execution
# are handled by an additional job execution.
#
# The lock keys are derived from the job arguments by default, and can be overridden with a
# custom proc if desired.
#
# WARNING: Any jobs using this module must be idempotent and stateless.
module LockingJob
  extend ActiveSupport::Concern
  extend T::Helpers

  DEFAULT_LOCK_TIMEOUT = 60 * 60 # 1 hour

  # Lock jobs by unique arguments by default.
  DEFAULT_LOCK_PROC = proc do |job|
    if job.arguments.empty?
      job.class.name
    else
      DEFAULT_LOCK_STRINGIFY_PROC.call(job.arguments)
    end
  end

  # Predictably stringify job arguments, including AR models.
  DEFAULT_LOCK_STRINGIFY_PROC = proc do |args|
    args.map do |obj|
      case obj
      when ApplicationRecord
        "#{obj.class.name}#{obj.id}"
      when Hash
        transformed = obj.transform_values do |value|
          DEFAULT_LOCK_STRINGIFY_PROC.call([value])
        end
        sorted = transformed.to_a.sort_by { |x| x.first.to_s }.map { |k, v| "#{k}:#{v}" }.join(",")
        "{#{sorted}}"
      when Array
        "[#{obj.map { |o| DEFAULT_LOCK_STRINGIFY_PROC.call([o]) }.join(',')}]"
      else
        obj.to_s
      end
    end.join(" ")
  end

  included do
    attr_writer :lock_key
    attr_accessor :enqueue_mutex

    class_attribute :_lock_key, instance_accessor: false
    class_attribute :_lock_timeout, instance_accessor: false

    retry_on_restraint_unable_to_lock
    retry_on_recoverable_redis_exceptions

    # Skip enqueueing if this job is a locking job and we can't acquire the enqueue mutex.
    around_enqueue do |job, block|
      if job.locking? && !job.acquire_enqueue_mutex
        MetricsClient.increment("active_job.enqueue-mutex-not-acquired", tags: { job: job.class.name })
        next
      end

      begin
        block.call
      rescue StandardError
        # If enqueue fails, clear the enqueue mutex so future enqueues are not blocked
        job.clear_enqueue_mutex if job.locking? && job.enqueue_mutex.present?
        raise
      end
    end

    # When performing a job, clear the enqueue mutex then attempt to obtain a lock for performing the job.
    # If acquiring the perform lock fails, the job will be retried and one of two things will happen
    # 1. The job will re-acquire the enqueue mutex and be able to retry after a wait period
    # 2. Another job will acquire the enqueue mutex before this job does
    #
    # In either case, a job will have been enqueued and will be performed once
    # the perform lock can be acquired.  All jobs using this locking mechanism
    # must be idempotent and stateless, so it doesn't really matter which job instance
    # is enqueued and performed.
    around_perform do |job, block|
      next block.call unless job.locking?

      job.clear_enqueue_mutex if job.enqueue_mutex.present?

      Restraint.lock!(job.lock_key, 1, job.class.lock_timeout) do
        block.call
      end
    end
  end

  module ClassMethods
    def lock_key
      _lock_key
    end

    # The name of the "lock set" where the key derived from arguments will be
    # set to implement locking.  Defaults to the name of the class.
    def lock_set_name
      name
    end

    def lock_timeout
      _lock_timeout.to_i
    end

    def locked_by(key:, timeout:)
      self._lock_key = key
      self._lock_timeout = timeout
    end
  end
  mixes_in_class_methods(ClassMethods)

  def serialize
    super.tap do |obj|
      # serialize lock data to the job payload so it's available during deserialization and perform
      obj["lock_key"] = lock_key
      obj["enqueue_mutex"] = enqueue_mutex.serialize if enqueue_mutex.present?
    end
  end

  def deserialize(job_data)
    super
    self.lock_key = job_data["lock_key"]
    if (mutex_data = job_data["enqueue_mutex"]).is_a?(Hash)
      self.enqueue_mutex = Restraint::Lock.from_hash(mutex_data)
    end
  end

  def acquire_enqueue_mutex
    enqueue_key = "enqueue:#{lock_key}"
    return true if enqueue_mutex.present? && Restraint.can_reenter?(enqueue_mutex, enqueue_key, 1)

    value = SecureRandom.hex
    lock = Restraint.obtain_lock(enqueue_key, 1, self.class.lock_timeout, value)
    return false unless lock.is_a?(Restraint::Lock) && lock.valid?

    self.enqueue_mutex = lock
    true
  rescue Redis::BaseError
    # Fail open.  If redis is having issues we don't want to block all job processing.
    true
  end

  def clear_enqueue_mutex
    return if enqueue_mutex.nil?

    enqueue_mutex.release!
    self.enqueue_mutex = nil
  end

  def lock_key
    return nil unless self.class.lock_timeout.positive? && self.class.lock_key.present?

    @lock_key ||= begin
      key = self.class.lock_key.call(self)
      key = DEFAULT_LOCK_STRINGIFY_PROC.call([key]) if key.present? && !key.is_a?(String)
      if key.nil?
        key
      else
        "#{self.class.lock_set_name}:#{Digest::SHA256.hexdigest(key)}"
      end
    end
  end

  def locking?
    lock_key.present?
  end
end
