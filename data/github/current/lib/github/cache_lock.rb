# typed: true
# frozen_string_literal: true

module GitHub
  # Legacy atomic locking mixin that for synchronization.
  #
  # Avoid using this in new code. Use HashLock or Redis::Mutex instead.
  module CacheLock
    # Lock on the given key and yield to the block only if the lock
    # was obtained.
    #
    # key - The string memcache key.
    # ttl - Maximum lock time. This is a safeguard for when lock keys are not
    #       released due to crash or something.
    #
    # Returns whatever the block returns if called; nil when the lock
    # was not obtained.
    def cache_lock(key, ttl = 1.hour)
      if cache_lock_obtain(key, ttl)
        begin
          yield
        ensure
          cache_lock_release(key)
        end
      end
    end

    # Obtain a cache lock.
    #
    # Returns truthy when obtained, false if the lock is already held.
    def cache_lock_obtain(key, ttl = 1.hour)
      timestamp = Time.now.iso8601
      redis_key = "cachelock-#{key}"
      cache_lock_redis.set(redis_key, timestamp, ex: ttl, nx: true)
    end

    # Release a cache lock.
    def cache_lock_release(key)
      redis_key = "cachelock-#{key}"
      cache_lock_redis.del(redis_key)
    end

    private

    def cache_lock_redis
      GitHub.legacy_redis
    end
  end
end
