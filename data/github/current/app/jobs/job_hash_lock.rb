# typed: true
# frozen_string_literal: true

class JobHashLock
  LOCK_SET_NAMESPACE = :resque
  LOCK_SET_PREFIX = "hashlock"

  def initialize(job)
    @job = job
    @lock_set_key = "#{LOCK_SET_PREFIX}:#{job.class.lock_set_name}"
  end

  # If you want to check the status of the lock, but without
  # the side effect of setting it
  def locked?
    now = Time.now.to_i
    old = redis.hget(lock_set_key, job.lock_key).to_i
    now <= old
  end

  # Public: Acquire a job lock.
  # Returns true if the lock was acquired.
  # Returns false if the was not acquired.
  def acquire_lock
    now = Time.now.to_i
    timeout = now + job.class.lock_timeout + 1
    tags = ["class:#{job.class.name.underscore}", "queue:#{job.queue_name}", "legacy:false"]

    # If we were able to acquire a new lock then this job isn't locked
    if redis.hsetnx(lock_set_key, job.lock_key, "#{timeout}:#{job.job_id}")
      GitHub.dogstats.increment("jobs.hash-lock.acquire", tags: tags)
      return true
    end

    # If an existing lock timeout exists, this job is locked
    old = redis.hget(lock_set_key, job.lock_key)&.split(":")&.first.to_i
    if now <= old
      GitHub.dogstats.increment("jobs.hash-lock.fail-to-aquire", tags: tags)
      return false
    end

    # This job is not locked but we need to update the timeout first
    redis.hset(lock_set_key, job.lock_key, "#{timeout}:#{job.job_id}")
    GitHub.dogstats.increment("jobs.hash-lock.acquire", tags: tags)
    true
  end

  # Public: Clear the lock
  def clear_lock
    value = redis.hget(lock_set_key, job.lock_key)
    return if value.nil?
    return if value.match(/:/) && value.split(":").last != job.job_id

    if redis.hdel(lock_set_key, job.lock_key) > 0
      tags = ["class:#{job.class.name.underscore}", "queue:#{job.queue_name}", "legacy:false"]
      GitHub.dogstats.increment("jobs.hash-lock.release", tags: tags)
    end
  end

  private

  attr_reader :job, :lock_set_key

  def redis
    @redis ||= Redis::Namespace.new(LOCK_SET_NAMESPACE, redis: GitHub.job_coordination_redis)
  end
end
