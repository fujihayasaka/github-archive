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
  end

  test "#at_limit? returns true if over limit" do
    Codespaces::PerUserRateLimiter.stubs(:max_tries).returns(2)

    refute Codespaces::PerUserRateLimiter.at_limit?(@user)

    Timecop.freeze do
      Codespaces::PerUserRateLimiter.increment(@user)
      Codespaces::PerUserRateLimiter.increment(@user)
    end
    assert Codespaces::PerUserRateLimiter.at_limit?(@user)
  end

  test "#at_limit? returns false if under limit" do
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
end
