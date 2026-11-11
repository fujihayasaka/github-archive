# typed: true
# frozen_string_literal: true

module GitHub
  module Redis

    # Implements a simple semaphore in Redis that can be shared across
    # processes. Each mutex is identified by `name` when first initializing.
    # The mutex has a default timeout of 60 seconds. After this time, the lock
    # is considered stale and it can be acquired by any process.
    #
    # Example
    #
    #     mutex = GitHub::Redis::Mutex.new 'foo'
    #     mutex.lock {
    #       # do some sensitive operations here
    #     }
    #
    class Mutex

      # Raised when a lock cannot be acquired
      LockError = Class.new StandardError

      attr_reader :timeout
      attr_reader :lock_key
      attr_reader :redis
      private :redis

      # Create a new Mutex that will lock on a given redis key. The name of
      # the key is used to lock the mutex. Any other mutex created with the
      # same name will be unable to obtain the lock until it is released or
      # until the timeout expires.
      #
      # name - The redis key to use for locking (String or Symbol)
      # opts - Options Hash
      #        :timeout - number seconds until the lock is invalidated
      #        :wait    - time in seconds to wait while acquiring the lock
      #        :sleep   - time in seconds to sleep between retries
      #
      def initialize(name, opts = {})
        @lock_key   = "#{self.class.name}-#{name}"
        @timeout    = opts.fetch(:timeout, 60)
        @wait_time  = opts.fetch(:wait, 1)
        @sleep_time = opts.fetch(:sleep, 0.2)
        @acquired   = false
        @redis      = GitHub.legacy_redis
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
      # Returns `true` if the unlock was successful; `false` if it was not.
      #
      def unlock
        if @acquired
          unlock!
          true
        else
          false
        end
      end

      # Forcibly unlock the mutex regardless of timeout or the mutex instance
      # that acquired the lock.
      #
      def unlock!
        redis.del(lock_key)
        @acquired = false
        self
      end

      # Attempts to obtain the lock and returns immediately. You have to
      # manually unlock the mutex when using this method.
      #
      # Returns `true` if the lock is acquired; `false` if not.
      #
      def try_lock
        now = Time.now.to_f
        expires = now + timeout

        # return true if we successfully acquired the lock
        return @acquired = true if redis.setnx(lock_key, expires)

        # see if the existing timeout is still valid and return false if it is
        # (we cannot acquire the lock during the timeout period)
        return @acquired = false if now <= redis.get(lock_key).to_f

        # otherwise set the timeout and ensure that no other worker has
        # acquired the lock
        @acquired = now > redis.getset(lock_key, expires).to_f
      rescue ::Redis::CannotConnectError, ::Redis::TimeoutError
        # If we can't read from Redis right now, be conservative and assume
        # that means we can't acquire a lock.
        GitHub.dogstats.increment(
          "redis.mutex.try_lock.error",
          tags: ["class:#{self.class.name}"]
        )
        @acquired = false
      end

      # Determine if the lock is currently held by any mutex.
      #
      # Returns `true` if the lock exists; `false` if not.
      #
      def locked?
        now = Time.now.to_f
        now <= redis.get(lock_key).to_f
      end

      # Internal: This method will attempt to obtain the lock. It will retry
      # up until the configured `wait` time is reached. If the lock cannot be
      # acquired then a LockError is raised.
      #
      # Returns `true` if the lock is acquired.
      # Raises LockError if the lock could not be acquired.
      #
      def lock_with_retry
        slept = 0
        loop do
          return true if try_lock

          raise(LockError, "Could not acquire exclusive lock") if slept >= @wait_time
          sleep(@sleep_time)
          slept += @sleep_time
        end
      end

    end  # Mutex
  end  # Redis
end  # GitHub
