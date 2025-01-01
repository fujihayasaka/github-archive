# typed: true
# frozen_string_literal: true

require "test_helper"

class CopilotLimiterRedisTest < GitHub::TestCase
  include GitHub::LoggerHelper
  setup do
    Copilot.limiter_redis.flushall
  end

  context ".get" do
    test "returns the value of the key" do
      Copilot.limiter_redis.set("key", "value")

      assert_equal "value", Copilot::LimiterRedis.get("key")
    end

    test "returns nil when the key does not exist" do
      assert_nil Copilot::LimiterRedis.get("key2")
    end

    test "returns nil when the circuit is open" do
      Resilient::CircuitBreaker.any_instance.stubs(:allow_request?).returns(false)

      assert_nil Copilot::LimiterRedis.get("key")
    end
  end

  context ".hmget" do
    test "returns the hash of the key" do
      Copilot.limiter_redis.set("key", "value")
      Copilot.limiter_redis.set("otherkey", "othervalue")
      assert_equal({ "key" => "value", "otherkey" => "othervalue" }, Copilot::LimiterRedis.mget(%w[key otherkey]))
    end

    test "returns an empty hash when the key does not exist" do
      assert_equal({ "key" => "0" }, Copilot::LimiterRedis.mget(["key"]))
    end

    test "returns an empty hash when the circuit is open" do
      Resilient::CircuitBreaker.any_instance.stubs(:allow_request?).returns(false)

      assert_equal({ "key" => "0" }, Copilot::LimiterRedis.mget(["key"]))
    end
  end

  context ".hset" do
    test "sets the hash value" do
      assert Copilot::LimiterRedis.hset("key", "field", "value")
      assert_equal({ "field" => "value" }, Copilot.limiter_redis.hgetall("key"))
    end

    test "returns false when the circuit is open" do
      Resilient::CircuitBreaker.any_instance.stubs(:allow_request?).returns(false)

      refute Copilot::LimiterRedis.hset("key", "field", "value")
    end
  end

  context ".set" do
    test "sets the value" do
      assert Copilot::LimiterRedis.set("key", "value")
      assert_equal "value", Copilot.limiter_redis.get("key")
    end

    test "returns false when the circuit is open" do
      Resilient::CircuitBreaker.any_instance.stubs(:allow_request?).returns(false)

      refute Copilot::LimiterRedis.set("key", "value")

      # check that the circuit is still open
      assert_nil Copilot::LimiterRedis.get("key")

      assert_nil Copilot.limiter_redis.get("key")
    end
  end
end
