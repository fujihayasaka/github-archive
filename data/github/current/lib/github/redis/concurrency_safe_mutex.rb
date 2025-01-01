# typed: true
# frozen_string_literal: true

module GitHub
  module Redis
    # Enhanced version of ::Mutex which accounts for time differences between the servers fighting for the same lock.
    class ConcurrencySafeMutex
      # Lua scripts below are evaluated by redis to ensure atomicity, with multiple operations contained
      # in each script; this lets us avoid extra network calls and blocks other callers between the operations.
      # For more information, see: https://redis.io/docs/interact/programmability/eval-intro/

      # Lock if possible, otherwise return the current value and its time to expiry in milliseconds.
      # https://redis.io/commands/set/
      # https://redis.io/commands/get/
      # https://redis.io/commands/pttl/
      LOCK_SCRIPT = <<-eos
        if redis.call("set", KEYS[1], ARGV[1], "nx", "px", ARGV[2]) then
          return 1
        else
          return {redis.call("get", KEYS[1]), redis.call("pttl", KEYS[1])}
        end
      eos

      # Unlock only if the value matches our expectations, otherwise another caller has obtained it.
      # https://redis.io/commands/get/
      # https://redis.io/commands/del/
      UNLOCK_SCRIPT = <<-eos
        if redis.call("get",KEYS[1]) == ARGV[1] then
          return redis.call("del",KEYS[1])
        else
          return 0
        end
      eos

      # Not used for security purposes: the redis script cache uses SHA-1 hashes, so we need to use them
      # here to evaluate our scripts after loading them.
      LOCK_SCRIPT_SHA = Digest::SHA1.hexdigest(LOCK_SCRIPT) # rubocop:disable GitHub/InsecureHashAlgorithm
      UNLOCK_SCRIPT_SHA = Digest::SHA1.hexdigest(UNLOCK_SCRIPT) # rubocop:disable GitHub/InsecureHashAlgorithm

      attr_reader :timeout
      attr_reader :lock_key
      attr_reader :redis
      private :redis

      # Create a new ConcurrencySafeMutex that will lock on a given redis key. The name of
      # the key is used to lock the mutex. Any other mutex created with the
      # same name will be unable to obtain the lock until it is released or
      # until the timeout expires.
      #
      # name - The redis key to use for locking (String or Symbol)
      # opts - Options Hash
      #        :timeout - number seconds until the lock is invalidated
      #        :wait    - time in seconds to wait while acquiring the lock
      #        :sleep   - time in seconds to sleep between retries
      #        :redis   - redis instance to use for locking
      #
      def initialize(name, opts = {})
        @lock_key          = "#{self.class.name}-#{name}"
        @timeout           = opts.fetch(:timeout, 60)
        @wait_time         = opts.fetch(:wait, 1)
        @sleep_time        = opts.fetch(:sleep, 0.2)
        @acquired          = false
        @acquired_with     = nil
        @redis             = opts.fetch(:redis, GitHub.job_coordination_redis)
      end

      # Attempts to obtain the lock. If given, the block will be executed and
      # the lock released after completion. If the lock cannot be acquired
      # then a LockError is raised and the block will not be run.
      #
      # Returns `true` or the value from the block if the lock was acquired.
      # Raises LockError if the lock could not be acquired.
      #
      def lock
        return lock_with_retry unless block_given?

        begin
          lock_with_retry
          yield
        ensure
          unlock
        end
      end

      # Attempt to release the lock. This method will only succeed if the lock
      # was originally acquired by this mutex instance.
      #
      def unlock
        retry_on_noscript = true
        begin
          redis.evalsha(UNLOCK_SCRIPT_SHA, [[lock_key, @acquired_with]])
          @acquired = false
          @acquired_with = nil
        rescue ::Redis::CommandError => e
          if e.message.include?("NOSCRIPT") && retry_on_noscript
            retry_on_noscript = false
            @redis.script("load", UNLOCK_SCRIPT)
            retry
          else
            raise e
          end
        end
      end

      # Forcibly unlock the mutex regardless of timeout or the mutex instance
      # that acquired the lock.
      #
      def unlock!
        redis.del(lock_key)
        @acquired = false
        @acquired_with = nil
        self
      end

      # Determine if the lock is currently held by any mutex.
      #
      # Returns `true` if the lock exists; `false` if not.
      #
      def locked?
        !!redis.get(lock_key)
      end

      private

      # Attempts to obtain the lock and returns immediately. You have to
      # manually unlock the mutex when using this method.
      #
      # Returns `true` if the lock is acquired; `false` if not.
      #
      def try_lock
        begin
          retry_on_noscript = true
          value = SecureRandom.uuid
          attempt = redis.evalsha(LOCK_SCRIPT_SHA, [[lock_key, value, timeout * 1000]])

          if attempt == 1
            @acquired_with = value
            @acquired = true
          else
            val, ttl = attempt
            @acquired_with = nil
            @acquired = false
          end
        rescue ::Redis::CannotConnectError, ::Redis::TimeoutError
          # If we can't read from Redis right now, be conservative and assume
          # that means we can't acquire a lock.
          GitHub.dogstats.increment(
            "redis.mutex.try_lock.error",
            tags: ["class:#{self.class.name}"]
          )
          @acquired_with = nil
          @acquired = false
        rescue ::Redis::CommandError => e
          if e.message.include?("NOSCRIPT") && retry_on_noscript
            retry_on_noscript = false
            @redis.script("load", LOCK_SCRIPT)
            retry
          else
            raise e
          end
        end
      end

      # Internal: This method will attempt to obtain the lock. It will retry
      # up until the configured `wait` time is reached. If the lock cannot be
      # acquired then a LockError is raised.
      #
      # Returns `true` if the lock is acquired.
      # Raises LockError if the lock could not be acquired.
      #
      def lock_with_retry
        elapsed = 0
        start_time = (Time.now.to_f * 1000).to_i
        while elapsed < @wait_time * 1000
          return true if try_lock

          sleep(@sleep_time)

          # Add 2 ms to the drift to account for Redis expire error
          # (https://redis.io/commands/expire/#expire-accuracy)
          # which is 0-1 ms, plus 1 ms min drift for small TTLs.
          drift = (timeout * 1000 * 0.01).to_i + 2
          elapsed = (Time.now.to_f * 1000).to_i - start_time + drift
        end
        raise(Mutex::LockError, "Could not acquire exclusive lock")
      end
    end
  end
end
