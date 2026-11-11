# frozen_string_literal: true

require "rate_limit"

class Throttler
  LEADER_BASE_KEY = "throttle:leader"
  TICKET_BASE_KEY = "throttle:tickets"
  TIMEOUT = 60.seconds.to_i

  TimeoutError = Class.new(StandardError)

  class Open
    def throttle
      yield
    end

    def health_check
      "noop"
    end

    def rate_limit
      nil
    end

    # Warn if any other method is called
    def method_missing(method, *_args)
      warn "#{self.class.name} does not implement '#{method}'"
      nil
    end

    def respond_to_missing?
      true
    end
  end

  def self.redis
    # Don't use the built-in Rails Redis connection, as that's designed for
    # caching so has super aggressive timeouts etc. This picks up the Redis
    # connection string environment variable automatically.
    Dependabot.redis
  end

  def self.build(name)
    return Open.new if Dependabot.enterprise?
    return Throttler.new_with_redis_limit(redis, name) if Rails.env.production?

    Open.new
  end

  def self.new_with_redis_limit(redis, name)
    rate_limit = RedisRateLimit.new(redis, "throttle:limit:#{name}")
    new(redis, name, rate_limit)
  end

  attr_reader :name, :redis, :rate_limit, :uuid

  def initialize(redis, name, rate_limit, max_cycles: nil, timeout: TIMEOUT)
    @redis = redis
    @name = name
    @rate_limit = rate_limit
    @max_cycles = max_cycles
    @timeout = timeout
    @uuid = SecureRandom.uuid
  end

  def throttle
    take_ticket
    yield
  end

  def health_check
    redis.set("#{ticket_key}:health_check", Time.zone.now.to_s)
    throttle do
      redis.get("#{ticket_key}:health_check")
    end
  end

  def print_tickets
    cycle do
      burn_tickets
      @rate_limit.refresh

      while @rate_limit.current?
        sleep(@rate_limit.ticket_interval)
        print_ticket
        ensure_leader
      end
    end
  end

  def print_ticket
    ticket = format("%<time>0.6f", time: Time.now.to_f)
    redis.multi do |transaction|
      transaction.lpush(ticket_key, ticket)
      # Expire tickets after resets + some 10 sec padding
      transaction.expireat(ticket_key, rate_limit.resets_at.to_i + 10)
    end

    ActiveSupport::Notifications.instrument(
      "throttler.print_ticket",
      ticket: ticket,
      throttler: name,
      key: ticket_key
    )

    ticket
  end

  def burn_tickets
    redis.del(ticket_key)
  end

  def take_leadership
    redis.multi do |transaction|
      transaction.del(leader_key)
      transaction.lpush(leader_key, uuid)
      transaction.expire(leader_key, rate_limit.frequency * 2)
    end

    ActiveSupport::Notifications.instrument(
      "throttler.leader.taken",
      throttler: name,
      node_id: uuid,
    )
  end

  # This key is unique per throttler instance
  def ticket_key
    "#{TICKET_BASE_KEY}:#{name}:#{uuid}"
  end

  def leader_ticket_key
    # Use a circular list to retrieve the leader UUID so we can use
    # redis to block until a leader appears or the timeout has passed.
    leader = redis.brpoplpush(leader_key, leader_key, timeout: @timeout)

    # If we haven't been able to find a leader in redis, there is no ticket key
    return unless leader

    "#{TICKET_BASE_KEY}:#{name}:#{leader}"
  end

  def current_leader
    # Check if a leader uuid is present, returning nil if it is not immediately
    # available.
    redis.lindex(leader_key, 0)
  end

  def leader_key
    "#{LEADER_BASE_KEY}:#{name}"
  end

  private

  def ensure_leader
    # Snapshot the leader uuid to avoid misreporting if it expires
    # before we log acknowledgement that we are not electing ourselves.
    if (leader_uuid = current_leader)
      if leader_uuid == uuid
        renew_leadership
      else
        acknowledge_leader(leader_uuid)
      end
    else
      take_leadership
    end
  end

  def renew_leadership
    redis.expire(leader_key, rate_limit.frequency * 2)

    ActiveSupport::Notifications.instrument(
      "throttler.leader.renewed",
      throttler: name,
      node_id: uuid,
    )
  end

  def acknowledge_leader(leader_uuid)
    ActiveSupport::Notifications.instrument(
      "throttler.leader.ack",
      throttler: name,
      node_id: uuid,
      leader_id: leader_uuid
    )
  end

  def take_ticket
    current_ticket_key = nil
    ticket = nil
    ActiveSupport::Notifications.instrument("throttler.take_ticket", throttler: name) do |payload|
      current_ticket_key = leader_ticket_key

      if current_ticket_key
        payload[:key] = current_ticket_key
      else
        payload[:timeout] = true
        raise TimeoutError, "Throttler timed out while waiting for a leader."
      end

      _key, ticket = redis.brpop(current_ticket_key, timeout: @timeout)
      if ticket
        payload[:timeout] = false
        payload[:ticket] = ticket
      else
        payload[:timeout] = true
        raise TimeoutError, "Throttler timed out while waiting for a ticket on #{current_ticket_key}."
      end

      ticket
    end
  end

  def cycle(&block)
    if @max_cycles
      @max_cycles.times(&block)
    else
      loop(&block)
    end
  end
end
