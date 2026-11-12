# typed: true
# frozen_string_literal: true

require "sorbet-runtime"

# Simple locking mechanism that allows up to N operations to run concurrently for a given key
module Restraint
  extend T::Sig

  class UnableToLock < StandardError
    attr_reader :key

    def initialize(key)
      @key = key
      super("Unable to obtain lock")
    end

    def failbot_context
      { key: }
    end
  end

  class Lock < T::Struct
    extend T::Sig

    const :key, String
    const :count, Integer
    const :expires_at, Time
    const :value, String
    prop :held, T::Boolean, default: true

    # Create a Lock instance from a hash, parsing the expires_at field if it's a string
    sig { params(hash: T::Hash[String, T.untyped], strict: T::Boolean).returns(Lock) }
    def self.from_hash(hash, strict: false)
      super({
        **hash,
        "expires_at" => hash["expires_at"].is_a?(String) ? Time.zone.parse(hash["expires_at"]) : hash["expires_at"],
      }, strict:)
    end

    sig { returns(T::Boolean) }
    def valid?
      held && expires_at.future?
    end

    sig { void }
    def release!
      Restraint.redis.del(key) if Restraint.redis.get(key) == value
      self.held = false
    end
  end

  # Public: Attempt to lock and yield if success
  #
  # base_key - a String representing the key you want to lock against
  # count    - an Integer representing the number of jobs that can run against this key
  # ttl      - an Integer or duration (e.g., 1.hour) representing when this key should be expired if the process is
  #            terminated abnormally
  # lock     - a Restraint::Lock instance that can be used to obtain a reentrant lock, provided that the keys match
  #
  # raises UnableToLock if unable to lock at this time
  # returns the result of the given block
  #
  # Example:
  #
  #   # attempt to obtain 1 out of 6 locks for `backups_33`, auto-expire the lock in 1 hour
  #   Restraint.lock!('backups_fs33', 6, 1.hour) { ... }
  #
  sig do
    type_parameters(:R).
      params(base_key: String,
             count: Integer,
             ttl: T.any(Integer, ActiveSupport::Duration),
             lock: T.nilable(Lock),
             blk: T.proc.params(lock: Lock).returns(T.type_parameter(:R))).
      returns(T.type_parameter(:R))
  end
  # rubocop:disable Lint/UnusedMethodArgument
  def self.lock!(base_key, count, ttl, lock: nil, &blk)
    # rubocop:enable Lint/UnusedMethodArgument
    value = SecureRandom.hex
    ttl_seconds = ttl.to_i
    if lock && can_reenter?(lock, base_key, count)
      yield lock
    elsif (lock = obtain_lock(base_key, count, ttl_seconds, value))
      begin
        yield lock
      ensure
        lock.release!
      end
    else
      raise UnableToLock, base_key
    end
  end

  sig { params(base_key: String, count: Integer).returns(T::Boolean) }
  def self.locked?(base_key, count)
    keys(base_key, count).all? { |key| redis.get(key).present? }
  end

  # Public: generate the list of keys that can be used for a lock
  #
  # base_key - a String representing the key you want to lock against
  # count    - an Integer representing the number of jobs that can run against this key
  #
  # Returns an Array of Strings, each representing a key name
  sig { params(base_key: String, count: Integer).returns(T::Array[String]) }
  def self.keys(base_key, count)
    (1..count).map { |ii| "#{base_key}:#{ii}" }
  end

  # Public: attempt to obtain a lock
  #
  # base_key - a String representing the key you want to lock against
  # count    - an Integer representing the number of jobs that can run against this key
  # ttl      - the expiration time for a lock before it's released automatically
  # value    - a String representing the value to set for the lock (useful for avoiding race conditions)
  #
  # Returns a `Restraint::Lock` on success, `false` on failure
  sig { params(base_key: String, count: Integer, ttl: Integer, value: String).returns(T.any(Lock, FalseClass)) }
  def self.obtain_lock(base_key, count, ttl, value = "1")
    expires_at = Time.now.utc + ttl

    keys(base_key, count).each do |key|
      return Lock.new(key:, count:, expires_at:, value:) if redis.set(key, value, nx: true, ex: ttl.to_i)
    end
    false
  end

  sig { returns(::Redis) }
  def self.redis
    @redis ||= Dependabot.redis
  end

  sig { params(redis: ::Redis).void }
  def self.redis=(redis)
    @redis = redis
  end

  # Returns `true` if it is safe to reenter the provided `restraint` lock.
  sig { params(lock: T.nilable(Lock), base_key: String, count: Integer).returns(T::Boolean) }
  def self.can_reenter?(lock, base_key, count)
    !lock.nil? &&
      lock.valid? &&
      keys(base_key, count).include?(lock.key)
  end
end
