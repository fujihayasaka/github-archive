# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

require "scientist"

class JobHashLock
  include Scientist
  LOCK_SET_NAMESPACE = :resque
  LOCK_SET_PREFIX = "hashlock"

  def initialize(job)
    @job = job
    @lock_set_key = "#{LOCK_SET_PREFIX}:#{job.class.lock_set_name}"
  end

  # If you want to check the status of the lock, but without
  # the side effect of setting it
  def locked?
    # Don't use hash lock on GHES yet (awaiting validation for upgrade procedure)
    return do_check_locked(job_lock_key: job.lock_key) if GitHub.enterprise?

    do_check_locked(job_lock_key: job.safe_lock_key)
  end

  # Public: Acquire a job lock.
  # Returns true if the lock was acquired.
  # Returns false if the was not acquired.
  def acquire_lock
    # Don't use hash lock on GHES yet
    return do_acquire_lock(job_lock_key: job.lock_key) if GitHub.enterprise?

    do_acquire_lock(job_lock_key: job.safe_lock_key)
  end

  # Public: Clear the lock
  def clear_lock
    # Don't use hash lock on GHES yet
    return do_clear_lock(job_lock_key: job.lock_key) if GitHub.enterprise?

    do_clear_lock(job_lock_key: job.safe_lock_key)
  end

  private

  attr_reader :job, :lock_set_key

  # This is the original implementation of lock acquisition. We should have it here
  # as a fall back in case any of the logic related to safe keys breaks anything with jobs.
  def do_acquire_lock(job_lock_key:)
    now = Time.now.to_i
    timeout = now + job.class.lock_timeout + 1

    lock_acquired = do_acquire_lock_from_redis(job_lock_key: job_lock_key, timeout: timeout, redis_instance: redis)

    if lock_acquired
      GitHub.dogstats.increment("jobs.hash-lock.acquire", tags: dd_tags)
      return true
    end

    GitHub.dogstats.increment("jobs.hash-lock.fail-to-aquire", tags: dd_tags)
    false
  end

  def do_acquire_lock_from_redis(job_lock_key:, timeout:, redis_instance:)
    # If we were able to acquire a new lock then this job isn't locked
    lock_acquired = redis_instance.hsetnx(lock_set_key, job_lock_key.to_s, "#{timeout}:#{job.job_id}")
    if lock_acquired
      return true
    end

    # If an existing lock timeout exists, this job is locked
    existing_timeout = redis_instance.hget(lock_set_key, job_lock_key)&.split(":")&.first.to_i
    now = Time.now.to_i
    if now <= existing_timeout
      return false
    end

    # This job is not locked but we need to update the timeout first
    redis_instance.hset(lock_set_key, job_lock_key, "#{timeout}:#{job.job_id}")

    true
  end

  def do_check_locked(job_lock_key:)
    do_check_locked_redis(job_lock_key: job_lock_key, redis_instance: redis)
  end

  def do_check_locked_redis(job_lock_key:, redis_instance:)
    now = Time.now.to_i
    timeout = redis_instance.hget(lock_set_key, job_lock_key.to_s).to_i

    # If the lock is set and the timeout is in the future, then the job is locked
    now <= timeout
  end

  def do_clear_lock(job_lock_key:)
    lock_cleared = do_clear_lock_redis(job_lock_key: job_lock_key, redis_instance: redis)
    if lock_cleared > 0
      GitHub.dogstats.increment("jobs.hash-lock.release", tags: dd_tags)
    end
  end

  def do_clear_lock_redis(job_lock_key:, redis_instance:)
    value = redis_instance.hget(lock_set_key, job_lock_key.to_s)

    return 0 if value.nil?
    return 0 if value.match(/:/) && value.split(":").last != job.job_id

    redis_instance.hdel(lock_set_key, job_lock_key.to_s)
  end

  def dd_tags
    return @dd_tags if defined?(@dd_tags)
    @dd_tags = ["class:#{job.class.name.underscore}", "queue:#{job.queue_name}", "legacy:false"]
  end

  def redis
    @redis ||= Redis::Namespace.new(LOCK_SET_NAMESPACE, redis: GitHub.new_job_coord_redis)
  end
end
