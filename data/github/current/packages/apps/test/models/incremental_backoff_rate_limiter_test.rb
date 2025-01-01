# typed: true
# frozen_string_literal: true

require "test_helper"

class IncrementalBackoffRateLimiterTest < GitHub::TestCase
  fixtures do
    @key = "foo"
  end

  setup do
    reset_redis_rate_limiter
  end

  test "DEFAULT_INTERVAL" do
    assert_equal 5, ::IncrementalBackoffRateLimiter::DEFAULT_INTERVAL
  end

  test "not at limit on first check" do
    rate_limiter = ::IncrementalBackoffRateLimiter.check(@key)
    refute_predicate rate_limiter, :at_limit?

    assert_equal ::IncrementalBackoffRateLimiter::DEFAULT_INTERVAL, rate_limiter.interval
  end

  test "extends the interval if checked more than once" do
    rate_limiter = ::IncrementalBackoffRateLimiter.check(@key)
    refute_predicate rate_limiter, :at_limit?

    assert_equal ::IncrementalBackoffRateLimiter::DEFAULT_INTERVAL, rate_limiter.interval

    rate_limiter = ::IncrementalBackoffRateLimiter.check(@key)
    assert_predicate rate_limiter, :at_limit?

    extended_interval = ::IncrementalBackoffRateLimiter::DEFAULT_INTERVAL * 2
    assert_equal extended_interval, rate_limiter.interval
  end

  test "is not at limit if checked after the interval" do
    IncrementalBackoffRateLimiter.stub_const(:DEFAULT_INTERVAL, 0.1) do
      rate_limiter = ::IncrementalBackoffRateLimiter.check(@key)
      refute_predicate rate_limiter, :at_limit?

      assert_equal ::IncrementalBackoffRateLimiter::DEFAULT_INTERVAL, rate_limiter.interval

      sleep(IncrementalBackoffRateLimiter::DEFAULT_INTERVAL * 1.5)

      rate_limiter = ::IncrementalBackoffRateLimiter.check(@key)
      refute_predicate rate_limiter, :at_limit?

      assert_equal ::IncrementalBackoffRateLimiter::DEFAULT_INTERVAL, rate_limiter.interval
    end
  end
end
