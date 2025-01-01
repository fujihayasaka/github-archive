# typed: true
# frozen_string_literal: true

require "sorbet-runtime"

module GitHub
  # simple locking mechanism that allows N jobs to be running under a given key
  class Restraint

    class UnableToLock < StandardError ; end

    class Lock < T::Struct

      const :key, String
      const :n, Integer
      const :expires_at, Time
      const :value, String
      prop :held, T::Boolean, default: true

      sig { returns(T::Boolean) }
      def valid?
        held && expires_at.future?
      end

      sig { void }
      def release!
        self.held = false
      end
    end

    sig { returns(::Redis) }
    attr_reader :redis
    private :redis

    # Public: Initialize a Restraint
    #
    # redis - an optional active Redis connection, defaults to
    # GitHub.job_coordination_redis
    #
    # Example:
    #
    #   restraint = GitHub::Restraint.new
    sig { void }
    def initialize
      @redis = GitHub.job_coordination_redis
    end

    # Public: Attempt to lock and yield if success
    #
    # base_key - a String representing the key you want to lock against
    # n        - an Integer representing the number of jobs that can run against this key
    # ttl      - an Integer representing when this key should be expired if the process is terminated abnormally
    # lock     - a Restraint::Lock instance that can be used to obtain a reentrant lock, provided that the keys match
    #
    # raises UnableToLock if unable to lock at this time
    # returns the result of the given block
    #
    # Example:
    #
    #   # attempt to obtain 1 out of 6 locks for `backups_33`, auto-expire the lock in 1 hour
    #   restraint.lock!('backups_fs33', 6, 1.hour) { ... }
    #
    sig do
      type_parameters(:R)
        .params(base_key: String, n: Integer, ttl: Integer, lock: T.nilable(Lock), block: T.proc.params(arg0: Lock).returns(T.type_parameter(:R)))
        .returns(T.type_parameter(:R))
    end
    def lock!(base_key, n, ttl, lock: nil, &block)
      value = SecureRandom.hex
      if lock && can_reenter?(lock, base_key, n)
        yield lock
      elsif lock = obtain_lock(base_key, n, ttl, value)
        begin
          yield lock
        ensure
          redis.del lock.key if redis.get(lock.key) == value
          lock.release!
        end
      else
        raise UnableToLock, "Unable to obtain lock"
      end
    end

    # Public: generate the list of keys that can be used for a lock
    #
    # base_key - a String representing the key you want to lock against
    # n        - an Integer representing the number of jobs that can run against this key
    #
    # Returns an Array of Strings, each representing a key name
    sig { params(base_key: String, n: Integer).returns(T::Array[String]) }
    def keys(base_key, n)
      (1..n).map { |ii| "#{base_key}:#{ii}" }
    end

    # Public: attempt to obtain a lock
    #
    # base_key - a String representing the key you want to lock against
    # n        - an Integer representing the number of jobs that can run against this key
    # ttl      - the expiration time for a lock before it's released automatically
    # value    - a String representing the value to set for the lock (useful for avoiding race conditions)
    #
    # Returns a `GitHub::Restraint::Key` on success, `false` on failure
    sig { params(base_key: String, n: Integer, ttl: Integer, value: String).returns(T.any(Lock, FalseClass)) }
    def obtain_lock(base_key, n, ttl, value = "1")
      expires_at = Time.now + ttl

      keys(base_key, n).each do |key|
        if redis.set(key, value, nx: true, ex: ttl.to_i)
          return Lock.new(key:, n:, expires_at:, value:)
        end
      end

      false
    rescue ::Redis::BaseError => e
      false
    end

    private

    # Returns `true` if it is safe to reenter the provided `restraint` lock.
    sig { params(lock: T.nilable(Lock), base_key: String, n: Integer).returns(T::Boolean) }
    def can_reenter?(lock, base_key, n)
      !lock.nil? &&
        lock.valid? &&
        keys(base_key, n).include?(lock.key)
    end
  end
end
