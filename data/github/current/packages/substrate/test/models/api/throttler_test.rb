# typed: true
# frozen_string_literal: true

require "test_helpers/api_serializer_helper"

class Api::ThrottlerTest < GitHub::TestCase
  setup do
    reset_redis_rate_limiter
  end

  def new_throttler(key, options)
    Api::Throttler.new(key, options)
  end

  test "Throttler default case with no specific implementation" do
    throttler = new_throttler("user-123", {
      max_tries: 100,
      ttl: 60,
      amount: 5,
    })

    rate = throttler.check

    assert_equal "user-123", rate.key
    assert_equal 0, rate.tries
    assert_equal false, rate.limit
    assert_equal 100, rate.max_tries
    assert_equal 100, rate.remaining

    throttler.rate!
    rate = throttler.rate!

    assert_equal 10, rate.tries
    assert_equal false, rate.limit
    assert_equal 90, rate.remaining
  end

  test "runway hides requests until the runway is used up" do
    key = "abc-123"
    # First, consume the runway. During this time, `remaining` stays the same:
    9.times do |i|
      throttler = new_throttler(key, runway: 90, max_tries: 10, amount: 10)
      result = throttler.rate!
      assert_equal 10, result.max_tries
      assert_equal 10, result.remaining
      assert_equal ((i + 1) * 10), result.tries
      refute result.at_limit?

      check = throttler.check
      assert_equal 10, result.max_tries
      assert_equal 10, result.remaining
      assert_equal ((i + 1) * 10), result.tries
      refute result.at_limit?
    end

    # Then, consume the first non-runway try, so `remaining` decreases:
    throttler = new_throttler(key, runway: 90, max_tries: 10, amount: 1)
    result = throttler.rate!
    assert_equal 10, result.max_tries
    assert_equal 9, result.remaining
    assert_equal 91, result.tries
    refute result.at_limit?

    check = throttler.check
    assert_equal 10, check.max_tries
    assert_equal 9, check.remaining
    assert_equal 91, check.tries
    refute check.at_limit?

    # Finally, consume the rest of the remaining tries, so `at_limit?` is true:
    throttler = new_throttler(key, runway: 90, max_tries: 10, amount: 9)
    result = throttler.rate!
    assert_equal 10, result.max_tries
    assert_equal 0, result.remaining
    assert_equal 100, result.tries
    assert result.at_limit?

    check = throttler.check
    assert_equal 10, check.max_tries
    assert_equal 0, check.remaining
    assert_equal 100, check.tries
    assert check.at_limit?

    # Usually this would be disallowed because of an earlier call to `.check`,
    # but let's make sure it doesn't blow up:
    throttler = new_throttler(key, runway: 90, max_tries: 10, amount: 1)
    result = throttler.rate!
    assert_equal 10, result.max_tries
    assert_equal 0, result.remaining
    assert_equal 101, result.tries
    assert result.at_limit?

    check = throttler.check
    assert_equal 10, check.max_tries
    assert_equal 0, check.remaining
    assert_equal 101, check.tries
    assert check.at_limit?
  end

  test "#rate!" do
    throttler = new_throttler("user-123", {
      max_tries: 100,
      ttl: 60,
      amount: 5,
    })

    rate = throttler.rate!

    assert_equal "user-123", rate.key
    assert_equal 5, rate.tries
    assert_equal false, rate.limit
    assert_equal 100, rate.max_tries
    assert_equal 95, rate.remaining
    assert rate.expires_at.is_a?(Time)
  end

  test "#check" do
    throttler = new_throttler("user-123", {
      max_tries: 100,
      ttl: 60,
      amount: 5,
    })

    rate = throttler.check

    assert_equal "user-123", rate.key
    assert_equal 0, rate.tries
    assert_equal false, rate.limit
    assert_equal 100, rate.max_tries
    assert_equal 100, rate.remaining
    assert rate.expires_at.is_a?(Time)
  end

  test "#check ignores unexpired, stale data (this can happen when Redis doesn't replicate expires)" do
    actor = create(:user, login: "abcd123")
    key = actor.login

    Timecop.freeze do
      # Setup the database so that the `TTL` hasn't arrived yet,
      # but the `:exp` value has already passed.
      # This is an exaggeration of stale replicated data (see https://github.com/redis/redis/issues/187)
      write_db = GitHub.rate_limiter_redis.shard_for(key).write
      write_db.set(key, 100)
      write_db.expire(key, 15)
      write_db.set(key + ":exp", Time.now.to_i - 1)

      throttler = new_throttler(key, {
        max_tries: 100,
        actor: actor,
        ttl: 60,
        amount: 5,
      })

      rate = throttler.check
      # It's a fresh window with a full ttl
      assert_equal 0, rate.tries
      assert_equal Time.now.to_i + 60, rate.expires_at.to_i

      updated_rate = throttler.rate!
      assert_equal 5, updated_rate.tries
      assert_equal Time.now.to_i + 60, updated_rate.expires_at.to_i
    end
  end

  test "kitchensink" do
    throttler = new_throttler("user-123", {
      max_tries: 100,
      ttl: 60,
      amount: 5,
    })

    rate = throttler.check

    assert_equal "user-123", rate.key
    assert_equal 0, rate.tries
    assert_equal false, rate.limit
    assert_equal 100, rate.max_tries
    assert_equal 100, rate.remaining

    throttler.rate!
    rate = throttler.rate!

    assert_equal 10, rate.tries
    assert_equal false, rate.limit
    assert_equal 90, rate.remaining
  end

  test "#at_limit" do
    throttler = new_throttler("user-123", {
      max_tries: 5,
      ttl: 60,
      amount: 5,
    })

    rate = throttler.check

    assert_equal "user-123", rate.key
    assert_equal 0, rate.tries
    assert_equal false, rate.limit
    assert_equal 5, rate.max_tries
    assert_equal 5, rate.remaining

    rate = throttler.rate!

    assert_equal 5, rate.tries
    assert_equal true, rate.limit
    assert_equal 0, rate.remaining

    rate = throttler.rate!

    assert_equal 10, rate.tries
    assert_equal true, rate.limit
    assert_equal 0, rate.remaining
  end

  test "#remove" do
    throttler = new_throttler("user-123", {
      max_tries: 100,
      ttl: 60,
      amount: 5,
    })

    rate = throttler.rate!

    assert_equal "user-123", rate.key
    assert_equal 5, rate.tries
    assert_equal false, rate.limit
    assert_equal 100, rate.max_tries
    assert_equal 95, rate.remaining

    read_db = GitHub.rate_limiter_redis.shard_for("user-123").read_only

    # Make sure the database is populated
    assert read_db.exists("v2:user-123")
    assert read_db.exists("v2:user-123:exp")

    throttler.remove!

    # Make sure the database is cleaned up
    refute read_db.exists("v2:user-123")
    refute read_db.exists("v2:user-123:exp")

    rate = throttler.rate!

    assert_equal "user-123", rate.key
    assert_equal 5, rate.tries
    assert_equal false, rate.limit
    assert_equal 100, rate.max_tries
    assert_equal 95, rate.remaining
  end
end
