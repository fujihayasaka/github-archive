# frozen_string_literal: true

require "rails_helper"
require "rate_limit"

RSpec.describe RedisRateLimit do
  # Clean redis, as the tickets are stored there
  let(:redis) { Dependabot.redis }
  let(:rate_limit) { described_class.new(redis, "test") }

  before { redis.flushdb }

  context "when limits are not set" do
    it "creates a throttler using default frequency" do
      expect(rate_limit.frequency).to eq(RedisRateLimit::DEFAULT_FREQUENCY)
    end

    it "creates a throttler using default limit" do
      expect(rate_limit.limit).to eq(RedisRateLimit::DEFAULT_LIMIT)
    end
  end

  context "when setting limits" do
    before { rate_limit.set_limit(42, 2.minutes) }

    it "creates a throttler using 1 minute frequency" do
      expect(rate_limit.frequency).to eq(2 * 60)
    end

    it "creates a throttler using 42 tickets limit" do
      expect(rate_limit.limit).to eq(42)
    end
  end

  context "locking against changes" do
    before { rate_limit.lock(reason: "bees in the data centre") }

    it "can be locked" do
      expect(rate_limit).to be_locked
    end

    it "can be unlocked" do
      rate_limit.unlock!

      expect(rate_limit).not_to be_locked
    end

    it "does not allow limit changes when locked" do
      expect(rate_limit.frequency).to eq(RedisRateLimit::DEFAULT_FREQUENCY)
      expect(rate_limit.limit).to eq(RedisRateLimit::DEFAULT_LIMIT)

      expect { rate_limit.set_limit(42, 2.minutes) }.
        to raise_error(RateLimit::LockedError, "bees in the data centre")

      expect(rate_limit.frequency).to eq(RedisRateLimit::DEFAULT_FREQUENCY)
      expect(rate_limit.limit).to eq(RedisRateLimit::DEFAULT_LIMIT)
    end

    it "allows limit changes once unlocked" do
      expect(rate_limit.frequency).to eq(RedisRateLimit::DEFAULT_FREQUENCY)
      expect(rate_limit.limit).to eq(RedisRateLimit::DEFAULT_LIMIT)

      rate_limit.unlock!

      expect { rate_limit.set_limit(42, 2.minutes) }.
        not_to raise_error

      expect(rate_limit.frequency).to eq(2 * 60)
      expect(rate_limit.limit).to eq(42)
    end
  end
end
