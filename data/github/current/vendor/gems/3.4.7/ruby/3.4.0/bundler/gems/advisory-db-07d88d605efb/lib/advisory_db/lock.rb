# frozen_string_literal: true

module AdvisoryDB
  class Lock
    DEFAULT_TTL = 3_600 # 1 hour

    AlreadyLocked = Class.new(StandardError)

    attr_reader :key, :ttl

    def initialize(key, ttl: DEFAULT_TTL)
      validate_key!(key)
      validate_ttl!(ttl)

      @key = key
      @ttl = ttl
      @mine = false
    end

    # Is this locked?
    def locked?
      redis.exists?(redis_key)
    end

    # Is this unlocked?
    def unlocked?
      !locked?
    end

    # Did I lock this?
    #
    # Returns true if this specific AdvisoryDB::Lock object locked this.
    # Returns false otherwise.
    def mine?
      @mine
    end

    # When was this locked?
    #
    # Returns a time in the current time zone if locked.
    # Returns nil if unlocked.
    def locked_at
      value = redis.get(redis_key)
      value ? Time.zone.at(value.to_i) : nil
    end

    # How long from now will the current lock expire?
    #
    # Returns the number of seconds from now when the current lock will expire.
    # Returns nil if unlocked or if (for some reason) there was no TTL set.
    def expires_in
      ttl = redis.ttl(redis_key)
      ttl >= 0 ? ttl : nil
    end

    # When will the current lock expire?
    #
    # Returns a time in the current time zone if locked.
    # Returns nil if unlocked or if (for some reason) there was no TTL set.
    def expires_at
      expires_in.try { |n| n.seconds.from_now }
    end

    # Obtains a lock, executes a block, and releases the lock (if possible).
    #
    # If the lock cannot be obtained, the block is never executed.
    #
    # WARNING: Using the wrap method when the lock cannot be obtained will fail
    # silently, giving no indication that the block was not executed. Consider
    # using the wrap! method instead.
    #
    # Returns the result of the given block.
    # Returns false if the lock could not be obtained.
    def wrap
      if lock
        begin
          yield
        ensure
          unlock
        end
      else
        false
      end
    end

    # Obtains a lock, executes a block, and releases the lock (if possible).
    #
    # The wrap! method behaves exactly like the wrap method except that if the
    # lock cannot be obtained, the wrap! method will immediately raise an
    # AlreadyLocked error.
    #
    # Returns the result of the given block.
    def wrap!
      lock!
      begin
        yield
      ensure
        unlock
      end
    end

    # Obtains a lock with a time-to-live in seconds.
    #
    # Returns true if the lock was successfully obtained and its TTL is set.
    # Returns false if the lock was previously obtained.
    def lock
      if redis.setnx(redis_key, Time.current.to_i.to_s)
        redis.expire(redis_key, ttl)
        @mine = true
      else
        false
      end
    end

    # Obtains a lock with a time-to-live in seconds.
    #
    # Returns true if the lock was successfully obtained and its TTL set.
    # Raises a LockCannotBeObtained error if the lock was previously obtained.
    def lock!
      lock || already_locked!
    end

    # Releases a lock.
    #
    # Returns true if the lock was released.
    # Returns false if the lock expired or never existed.
    def unlock
      @mine = false
      redis.del(redis_key) > 0
    end

    private

    def validate_key!(key)
      return if key.is_a?(String)

      raise ArgumentError,
        "The key must be a string. Got: #{key.inspect}"
    end

    def validate_ttl!(ttl)
      return if ttl.is_a?(Integer) && ttl >= 0

      raise ArgumentError,
        "The TTL must be a positive integer. Got: #{ttl.inspect}"
    end

    def already_locked!
      message = "The #{key.inspect} key was already locked"
      message += " by you" if mine?
      message += " at #{expires_at}" if expires_at
      raise AlreadyLocked, message
    end

    def redis
      AdvisoryDB.redis
    end

    def redis_key
      @redis_key ||= "lock:#{key}"
    end
  end
end
