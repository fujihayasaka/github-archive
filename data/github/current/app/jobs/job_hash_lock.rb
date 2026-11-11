# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

require "scientist"

class JobHashLock
  include Scientist
  LOCK_SET_NAMESPACE = :resque
  LOCK_SET_PREFIX = "hashlock"

  # Feature flags for migrating from Redis hashes to flat key/value pairs.
  FLAT_KEY_DUAL_WRITE_FLAG = :job_hash_lock_flat_key_dual_write
  FLAT_KEY_READ_FLAG = :job_hash_lock_flat_key_read
  FLAT_KEY_ONLY_FLAG = :job_hash_lock_flat_key_only

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

  # Public: Datadog tags for metrics related to this lock.
  def dd_tags
    return @dd_tags if defined?(@dd_tags)
    @dd_tags = [
      "class:#{job.class.name.underscore}",
      "queue:#{job.queue_name}",
      "legacy:false",
      "lock_backend:#{lock_backend_phase}",
    ]
  end

  private

  attr_reader :job, :lock_set_key

  # This is the original implementation of lock acquisition. We should have it here
  # as a fall back in case any of the logic related to safe keys breaks anything with jobs.
  def do_acquire_lock(job_lock_key:)
    if any_flat_key_flag_enabled?
      return do_acquire_lock_flat_migration(job_lock_key: job_lock_key)
    end

    now = Time.now.to_i
    timeout = now + job.class.lock_timeout + 1

    lock_acquired = do_acquire_lock_from_redis(job_lock_key: job_lock_key, timeout: timeout, redis_instance: redis)

    if lock_acquired
      GitHub.dogstats.increment("jobs.hash_lock.acquire", tags: dd_tags)
      return true
    end

    GitHub.dogstats.increment("jobs.hash_lock.fail_to_aquire", tags: dd_tags)
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
    if any_flat_key_flag_enabled?
      return do_check_locked_flat_migration(job_lock_key: job_lock_key)
    end

    do_check_locked_redis(job_lock_key: job_lock_key, redis_instance: redis)
  end

  def do_check_locked_redis(job_lock_key:, redis_instance:)
    now = Time.now.to_i
    timeout = redis_instance.hget(lock_set_key, job_lock_key.to_s).to_i

    # If the lock is set and the timeout is in the future, then the job is locked
    now <= timeout
  end

  def do_clear_lock(job_lock_key:)
    if any_flat_key_flag_enabled?
      return do_clear_lock_flat_migration(job_lock_key: job_lock_key)
    end

    lock_cleared = do_clear_lock_redis(job_lock_key: job_lock_key, redis_instance: redis)
    if lock_cleared > 0
      GitHub.dogstats.increment("jobs.hash_lock.release", tags: dd_tags)
    end
  end

  def do_clear_lock_redis(job_lock_key:, redis_instance:)
    value = redis_instance.hget(lock_set_key, job_lock_key.to_s)

    return 0 if value.nil?
    return 0 if value.match(/:/) && value.split(":").last != job.job_id

    redis_instance.hdel(lock_set_key, job_lock_key.to_s)
  end

  # --- Flat key migration ---
  #
  # The methods below implement the phased migration from Redis hashes to flat
  # key/value pairs. They are only called when at least one migration flag is on.
  #
  # Phases:
  #   dual_write  -> hash write + flat write, hash read
  #   flat_read   -> hash write + flat write, flat read
  #   flat_only   -> flat write only, flat read

  def do_acquire_lock_flat_migration(job_lock_key:)
    flat_only = flag_enabled?(FLAT_KEY_ONLY_FLAG)
    dual_write = flag_enabled?(FLAT_KEY_DUAL_WRITE_FLAG)
    flat_read = flag_enabled?(FLAT_KEY_READ_FLAG)

    # Write to hash (unless flat_only)
    unless flat_only
      now = Time.now.to_i
      timeout = now + job.class.lock_timeout + 1
      hash_result = do_acquire_lock_from_redis(job_lock_key: job_lock_key, timeout: timeout, redis_instance: redis)
    end

    # Write to flat key. When hash is also being written (dual_write/flat_read),
    # skip the flat write if hash acquisition failed to keep the two stores in sync.
    if flat_only || ((dual_write || flat_read) && hash_result)
      flat_result = do_acquire_lock_flat(job_lock_key: job_lock_key)
    end

    # Read result from the authoritative source
    result = (flat_read || flat_only) ? flat_result : hash_result

    if result
      GitHub.dogstats.increment("jobs.hash_lock.acquire", tags: dd_tags)
    else
      GitHub.dogstats.increment("jobs.hash_lock.fail_to_aquire", tags: dd_tags)
    end

    result
  end

  def do_check_locked_flat_migration(job_lock_key:)
    if flag_enabled?(FLAT_KEY_READ_FLAG) || flag_enabled?(FLAT_KEY_ONLY_FLAG)
      value = redis.get(flat_key(job_lock_key))
      return false if value.nil?

      timeout = value.split(":").first.to_i
      Time.now.to_i <= timeout
    else
      do_check_locked_redis(job_lock_key: job_lock_key, redis_instance: redis)
    end
  end

  def do_clear_lock_flat_migration(job_lock_key:)
    flat_only = flag_enabled?(FLAT_KEY_ONLY_FLAG)
    dual_write = flag_enabled?(FLAT_KEY_DUAL_WRITE_FLAG)
    flat_read = flag_enabled?(FLAT_KEY_READ_FLAG)

    # Clear from hash (unless flat_only)
    unless flat_only
      hash_cleared = do_clear_lock_redis(job_lock_key: job_lock_key, redis_instance: redis)
    end

    # Clear from flat key (if dual_write, flat_read, or flat_only)
    if dual_write || flat_read || flat_only
      flat_cleared = do_clear_lock_flat(job_lock_key: job_lock_key)
    end

    cleared = (flat_read || flat_only) ? flat_cleared : hash_cleared
    if cleared && cleared > 0
      GitHub.dogstats.increment("jobs.hash_lock.release", tags: dd_tags)
    end
  end

  # Acquire a lock using a flat Redis key with SET NX EX.
  # Stores "timeout:job_id" as the value (matching the hash implementation) so
  # that application-level timeout checks work with time travel in tests.
  # Redis TTL serves as a wall-clock safety net for expiry.
  def do_acquire_lock_flat(job_lock_key:)
    now = Time.now.to_i
    timeout = now + job.class.lock_timeout + 1
    ttl = job.class.lock_timeout + 1
    flat_value = "#{timeout}:#{job.job_id}"

    result = redis.set(flat_key(job_lock_key), flat_value, nx: true, ex: ttl)
    return true if result

    # Key exists -- check if the lock has expired via application-level timeout.
    existing_value = redis.get(flat_key(job_lock_key))
    if existing_value.nil?
      # Key expired between SET and GET -- retry the atomic SET NX EX.
      retry_result = redis.set(flat_key(job_lock_key), flat_value, nx: true, ex: ttl)
      return retry_result ? true : false
    end

    # Check application-level timeout (supports time travel in tests)
    existing_timeout = existing_value.split(":").first.to_i
    if now > existing_timeout
      # Lock has expired -- overwrite it
      redis.set(flat_key(job_lock_key), flat_value, ex: ttl)
      return true
    end

    false
  end

  # Clear a flat key lock, but only if it was set by this job instance.
  def do_clear_lock_flat(job_lock_key:)
    value = redis.get(flat_key(job_lock_key))

    return 0 if value.nil?

    stored_job_id = value.match?(/:/) ? value.split(":", 2).last : value
    return 0 if stored_job_id != job.job_id

    redis.del(flat_key(job_lock_key))
  end

  # Build the flat Redis key for a given lock key.
  # Format: "hashlock:{ClassName}:{lock_key}"
  def flat_key(job_lock_key)
    "#{LOCK_SET_PREFIX}:#{job.class.lock_set_name}:#{job_lock_key}"
  end

  # --- Shared helpers ---

  def any_flat_key_flag_enabled?
    flag_enabled?(FLAT_KEY_DUAL_WRITE_FLAG) ||
      flag_enabled?(FLAT_KEY_READ_FLAG) ||
      flag_enabled?(FLAT_KEY_ONLY_FLAG)
  end

  def flag_enabled?(flag)
    FeatureFlag.vexi.enabled?(flag, default: false)
  end

  def lock_backend_phase
    if flag_enabled?(FLAT_KEY_ONLY_FLAG)
      "flat_key_only"
    elsif flag_enabled?(FLAT_KEY_READ_FLAG)
      "flat_key_read"
    elsif flag_enabled?(FLAT_KEY_DUAL_WRITE_FLAG)
      "dual_write"
    else
      "hash"
    end
  end

  def redis
    @redis ||= Redis::Namespace.new(LOCK_SET_NAMESPACE, redis: GitHub.new_job_coord_redis)
  end
end
