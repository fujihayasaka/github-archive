# typed: true
# frozen_string_literal: true

require "test_helper"

class CodespacesPerUserRateLimiterTest < GitHub::TestCase
  setup_once do
    enable_cache_storage
  end

  teardown_once do
    disable_cache_storage
  end

  setup do
    reset_cache
    reset_monolith_redis_rate_limiter
    @user = create(:user)
    GitHub.flipper[:codespaces_automated_testing].disable
    GitHub.flipper[:codespaces_bypass_rate_limiting].disable
    GitHub.flipper[:codespaces_extended_rate_limiting].enable
    Codespaces::Dials::ExtendedRateLimitDurationMinutes.any_instance.stubs(:value).returns(10)
  end

  test "#at_limit? returns true if over 1 minute limit" do
    Codespaces::PerUserRateLimiter.stubs(:max_tries).returns(2)

    refute Codespaces::PerUserRateLimiter.at_limit?(@user)

    Timecop.freeze do
      Codespaces::PerUserRateLimiter.increment(@user)
      Codespaces::PerUserRateLimiter.increment(@user)
    end
    assert Codespaces::PerUserRateLimiter.at_limit?(@user)
  end

  test "#at_limit? returns true if over 10 minute limit" do
    Codespaces::PerUserRateLimiter.stubs(:max_tries).returns(3)
    Codespaces::Dials::ExtendedRateLimitMaxOperations.any_instance.stubs(:value).returns(2)

    refute Codespaces::PerUserRateLimiter.at_limit?(@user)

    Timecop.freeze do
      Codespaces::PerUserRateLimiter.increment(@user)
      Codespaces::PerUserRateLimiter.increment(@user)
    end
    assert Codespaces::PerUserRateLimiter.at_limit?(@user)
  end

  test "#at_limit? returns false if over 10 minute limit, with feature flag disabled" do
    GitHub.flipper[:codespaces_extended_rate_limiting].disable
    Codespaces::PerUserRateLimiter.stubs(:max_tries).returns(3)
    Codespaces::Dials::ExtendedRateLimitMaxOperations.any_instance.stubs(:value).returns(2)

    refute Codespaces::PerUserRateLimiter.at_limit?(@user)

    Timecop.freeze do
      Codespaces::PerUserRateLimiter.increment(@user)
      Codespaces::PerUserRateLimiter.increment(@user)
    end
    refute Codespaces::PerUserRateLimiter.at_limit?(@user)
  end

  test "#at_limit? returns false if under 1 minute limit" do
    Codespaces::PerUserRateLimiter.any_instance.stubs(:key).returns("fake_key")
    Codespaces::PerUserRateLimiter.stubs(:max_tries).returns(2)

    refute Codespaces::PerUserRateLimiter.at_limit?(@user)

    Timecop.freeze do
      Codespaces::PerUserRateLimiter.increment(@user)
    end
    refute Codespaces::PerUserRateLimiter.at_limit?(@user)
  end

  test "#at_limit? returns false if tries were too long ago" do
    Codespaces::PerUserRateLimiter.any_instance.stubs(:key).returns("fake_key")
    Codespaces::PerUserRateLimiter.stubs(:max_tries).returns(2)

    refute Codespaces::PerUserRateLimiter.at_limit?(@user)

    Timecop.freeze(65.minutes.ago) do
      Codespaces::PerUserRateLimiter.increment(@user)
      Codespaces::PerUserRateLimiter.increment(@user)
    end
    refute Codespaces::PerUserRateLimiter.at_limit?(@user)
  end

  test "#at_limit? returns true if tries were too long ago for 1 minute limit, but not 10 minute limit" do
    Codespaces::PerUserRateLimiter.any_instance.stubs(:key).returns("fake_key")
    Codespaces::PerUserRateLimiter.stubs(:max_tries).returns(1)
    Codespaces::Dials::ExtendedRateLimitMaxOperations.any_instance.stubs(:value).returns(2)

    refute Codespaces::PerUserRateLimiter.at_limit?(@user)

    Timecop.freeze(8.minutes.ago) do
      Codespaces::PerUserRateLimiter.increment(@user)
      Codespaces::PerUserRateLimiter.increment(@user)
    end
    assert Codespaces::PerUserRateLimiter.at_limit?(@user)
  end
end
