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
  end

  # If you want to check the status of the lock, but without
  # the side effect of setting it
  def locked?
    # Don't use hash lock on GHES yet (awaiting validation for upgrade procedure)
    return lock_active?(job.lock_key) if GitHub.enterprise?

    lock_active?(job.safe_lock_key)
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

  # Public: Datadog tags for metrics related to this lock.
  def dd_tags
    return @dd_tags if defined?(@dd_tags)
    @dd_tags = [
      "class:#{job.class.name.underscore}",
      "queue:#{job.queue_name}",
      "legacy:false",
    ]
  end

  private

  attr_reader :job

  def do_acquire_lock(job_lock_key:)
    ttl = job.class.lock_timeout + 1
    lock_value = "#{Time.now.to_i + ttl}:#{job.job_id}"

    # Try atomic acquire first.
    if redis.set(redis_key(job_lock_key), lock_value, nx: true, ex: ttl)
      GitHub.dogstats.increment("jobs.hash_lock.acquire", tags: dd_tags)
      return true
    end

    # Lock key exists -- check if the existing lock has expired.
    if lock_active?(job_lock_key)
      GitHub.dogstats.increment("jobs.hash_lock.fail_to_aquire", tags: dd_tags)
      return false
    end

    # Lock is either missing (expired via Redis TTL between SET and GET)
    # or expired via application-level timeout -- (re)acquire it.
    redis.set(redis_key(job_lock_key), lock_value, ex: ttl)
    GitHub.dogstats.increment("jobs.hash_lock.acquire", tags: dd_tags)
    true
  end

  def do_clear_lock(job_lock_key:)
    value = redis.get(redis_key(job_lock_key))
    return if value.nil?

    stored_job_id = value.split(":", 2).last
    return if stored_job_id != job.job_id

    deleted = redis.del(redis_key(job_lock_key))
    GitHub.dogstats.increment("jobs.hash_lock.release", tags: dd_tags) if deleted > 0
  end

  # Returns true if the lock key exists and has not expired.
  # Checks application-level timeout (not just Redis TTL) to
  # support time travel in tests.
  def lock_active?(job_lock_key)
    value = redis.get(redis_key(job_lock_key))
    return false if value.nil?

    Time.now.to_i <= value.split(":").first.to_i
  end

  # Build the Redis key for a given lock key.
  # Format: "hashlock:{ClassName}:{lock_key}"
  def redis_key(job_lock_key)
    "#{LOCK_SET_PREFIX}:#{job.class.lock_set_name}:#{job_lock_key}"
  end

  def redis
    @redis ||= Redis::Namespace.new(LOCK_SET_NAMESPACE, redis: GitHub.job_coord_redis)
  end
end
