# frozen_string_literal: true

class RateLimit
  attr_reader :limit, :frequency, :resets_at

  class LockedError < StandardError; end

  def initialize(limit, frequency)
    @limit = limit
    @frequency = frequency
    refresh
  end

  def current?
    @resets_at.future?
  end

  def ticket_interval
    @frequency.to_i / @limit.to_f
  end

  def refresh
    @resets_at = Time.zone.now + @frequency
  end

  def locked?
    lock_reason.present?
  end

  def lock(*)
    false
  end

  def unlock!
    true
  end

  def lock_reason
    nil
  end
end

class RedisRateLimit < RateLimit
  DEFAULT_FREQUENCY = 2.seconds
  DEFAULT_LIMIT = 30

  def initialize(redis, base_key)
    @redis = redis
    @base_key = base_key
    super(nil, nil)
  end

  def refresh
    # default to 900 tickets a minute
    @frequency = (@redis.get("#{@base_key}:f") || DEFAULT_FREQUENCY).to_i
    @limit = (@redis.get("#{@base_key}:n") || DEFAULT_LIMIT).to_i
    super
  end

  def set_limit(limit, frequency)
    raise LockedError, lock_reason if locked?

    @redis.set("#{@base_key}:f", frequency)
    @redis.set("#{@base_key}:n", limit)
    refresh
  end

  def lock(reason:)
    @redis.set("#{@base_key}:locked", reason)
  end

  def lock_reason
    @redis.get("#{@base_key}:locked")
  end

  def unlock!
    @redis.del("#{@base_key}:locked")
  end
end
