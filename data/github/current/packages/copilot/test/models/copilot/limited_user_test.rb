# typed: true
# frozen_string_literal: true

require "test_helper"

class CopilotLimitedUserTest < GitHub::TestCase
  include GitHub::LoggerHelper
  include CopilotTestHelper # automatically disables Copilot feature flags

  fixtures do
    @user = create(:user)
  end

  setup do
    Copilot.redis.stubs(:hgetall).with(Copilot::LimitedUser::QUOTAS_KEY).returns({ "chat" => "50", "completions" => "2000" })
  end

  context "subscribed?" do
    test "returns false if subcribed_at is nil" do
      limited_user = create(:copilot_limited_user, user: create(:user), subscribed_at: nil)
      refute limited_user.subscribed?
    end

    test "returns true if subscribed_at is set" do
      limited_user = create(:copilot_limited_user, user: create(:user), subscribed_at: Time.now)
      assert limited_user.subscribed?
    end
  end

  context "reset_date" do
    test "returns nil if subcribed_at is nil" do
      limited_user = create(:copilot_limited_user, user: create(:user), subscribed_at: nil)
      assert_nil limited_user.reset_date
    end

    test "returns next month if subcribed_at is set" do
      travel_to Time.new(2022, 1, 1) do
        limited_user = create(:copilot_limited_user, user: create(:user), subscribed_at: Time.new(2022, 1, 1))
        limited_user.reload
        assert_equal limited_user.subscribed_at, Time.new(2022, 1, 1)
        assert_equal Date.new(2022, 2, 1), limited_user.reset_date
      end
    end
  end

  context "feature_allowed?" do
    test "returns false if user is not present" do
      limited_user = create(:copilot_limited_user, user: create(:user), subscribed_at: Time.now)
      limited_user.user = nil
      limited_user.save
      refute limited_user.feature_allowed?(feature: "chat")
    end

    test "returns false if subscribed_at is nil" do
      limited_user = create(:copilot_limited_user, user: create(:user), subscribed_at: nil)
      refute limited_user.feature_allowed?(feature: "chat")
    end

    test "returns false if feature is not in ALLOWED_FEATURES" do
      limited_user = create(:copilot_limited_user, user: create(:user), subscribed_at: Time.now)
      refute limited_user.feature_allowed?(feature: "foo")
    end

    test "returns true if the key is empty" do
      Copilot.redis.stubs(:hgetall).with(Copilot::LimitedUser::QUOTAS_KEY).returns({ "chat" => "50", "completions" => "2000" })
      feature = "chat"
      limited_user = create(:copilot_limited_user, user: create(:user), subscribed_at: Time.now)
      assert limited_user.feature_allowed?(feature: feature)
    end

    test "returns false if they have no quota left" do
      feature = "chat"
      limited_user = create(:copilot_limited_user, user: create(:user), subscribed_at: Time.now)
      limited_user.set_quota_remaining(feature: feature, quota: 0)
      refute limited_user.feature_allowed?(feature: feature)
    end

    test "returns true if they have quota left" do
      Copilot.redis.stubs(:hgetall).with(Copilot::LimitedUser::QUOTAS_KEY).returns({ "chat" => "50", "completions" => "2000" })
      feature = "chat"
      limited_user = create(:copilot_limited_user, user: create(:user), subscribed_at: Time.now)
      limited_user.set_quota_remaining(feature: feature, quota: 10)
      assert limited_user.feature_allowed?(feature: feature)
    end
  end

  context "feature_quota_remaining" do
    test "returns -1 if user is not present" do
      limited_user = create(:copilot_limited_user, user: create(:user), subscribed_at: Time.now)
      limited_user.user = nil
      limited_user.save
      assert_equal -1, limited_user.feature_quota_remaining(feature: "chat")
    end

    test "returns -1 if subscribed_at is nil" do
      limited_user = create(:copilot_limited_user, user: create(:user), subscribed_at: nil)
      assert_equal -1, limited_user.feature_quota_remaining(feature: "chat")
    end

    test "returns -1 if feature is not in ALLOWED_FEATURES" do
      limited_user = create(:copilot_limited_user, user: create(:user), subscribed_at: Time.now)
      assert_equal -1, limited_user.feature_quota_remaining(feature: "foo")
    end

    test "returns the monthly quota amount if the key is empty" do
      Copilot.redis.stubs(:hgetall).with(Copilot::LimitedUser::QUOTAS_KEY).returns({ "chat" => "50", "completions" => "2000" })
      feature = "chat"
      limited_user = create(:copilot_limited_user, user: create(:user), subscribed_at: Time.now)
      assert_equal 50, limited_user.feature_quota_remaining(feature: feature)
    end

    test "returns 10 if the key is 10" do
      Copilot.redis.stubs(:hgetall).with(Copilot::LimitedUser::QUOTAS_KEY).returns({ "chat" => "50", "completions" => "2000" })
      feature = "chat"
      limited_user = create(:copilot_limited_user, user: create(:user), subscribed_at: Time.now)
      Copilot.redis.set(limited_user.feature_count_key(feature), "10")
      assert_equal 40, limited_user.feature_quota_remaining(feature: feature)
    end
  end

  context "feature_quota_percentage_remaining" do
    test "returns 100 if user is not present" do
      limited_user = create(:copilot_limited_user, user: create(:user), subscribed_at: Time.now)
      limited_user.user = nil
      limited_user.save
      assert_equal 100.0, limited_user.feature_quota_percentage_remaining(feature: "chat")
    end

    test "returns 100 if subscribed_at is nil" do
      limited_user = create(:copilot_limited_user, user: create(:user), subscribed_at: nil)
      assert_equal 100.0, limited_user.feature_quota_percentage_remaining(feature: "chat")
    end

    test "returns 0.0 if feature is not in ALLOWED_FEATURES" do
      limited_user = create(:copilot_limited_user, user: create(:user), subscribed_at: Time.now)
      assert_equal 0.0, limited_user.feature_quota_percentage_remaining(feature: "foo")
    end

    test "returns the 100.0 if the key is empty" do
      Copilot.redis.stubs(:hgetall).with(Copilot::LimitedUser::QUOTAS_KEY).returns({ "chat" => "50" })
      feature = "chat"
      limited_user = create(:copilot_limited_user, user: create(:user), subscribed_at: Time.now)
      assert_equal 100.0, limited_user.feature_quota_percentage_remaining(feature: feature)
    end

    test "returns 80.0 if the user has 1/5 used" do
      Copilot.redis.stubs(:hgetall).with(Copilot::LimitedUser::QUOTAS_KEY).returns({ "chat" => "50" })
      feature = "chat"
      limited_user = create(:copilot_limited_user, user: create(:user), subscribed_at: Time.now)
      Copilot.redis.set(limited_user.feature_count_key(feature), "10")
      assert_equal 80.0, limited_user.feature_quota_percentage_remaining(feature: feature)
    end

    test "returns 60.0 if the user has 2/5 used" do
      Copilot.redis.stubs(:hgetall).with(Copilot::LimitedUser::QUOTAS_KEY).returns({ "chat" => "50" })
      feature = "chat"
      limited_user = create(:copilot_limited_user, user: create(:user), subscribed_at: Time.now)
      Copilot.redis.set(limited_user.feature_count_key(feature), "20")
      assert_equal 60.0, limited_user.feature_quota_percentage_remaining(feature: feature)
    end

    test "returns 40.0 if the user has 3/5 used" do
      Copilot.redis.stubs(:hgetall).with(Copilot::LimitedUser::QUOTAS_KEY).returns({ "chat" => "50" })
      feature = "chat"
      limited_user = create(:copilot_limited_user, user: create(:user), subscribed_at: Time.now)
      Copilot.redis.set(limited_user.feature_count_key(feature), "30")
      assert_equal 40.0, limited_user.feature_quota_percentage_remaining(feature: feature)
    end

    test "returns 20.0 if the user has 4/5 used" do
      Copilot.redis.stubs(:hgetall).with(Copilot::LimitedUser::QUOTAS_KEY).returns({ "chat" => "50" })
      feature = "chat"
      limited_user = create(:copilot_limited_user, user: create(:user), subscribed_at: Time.now)
      Copilot.redis.set(limited_user.feature_count_key(feature), "40")
      assert_equal 20.0, limited_user.feature_quota_percentage_remaining(feature: feature)
    end

    test "returns 0.0 if the user has 5/5 used" do
      Copilot.redis.stubs(:hgetall).with(Copilot::LimitedUser::QUOTAS_KEY).returns({ "chat" => "50" })
      feature = "chat"
      limited_user = create(:copilot_limited_user, user: create(:user), subscribed_at: Time.now)
      Copilot.redis.set(limited_user.feature_count_key(feature), "50")
      assert_equal 0.0, limited_user.feature_quota_percentage_remaining(feature: feature)
    end
  end

  context "quotas_remaining" do
    test "returns empty hash if user is not present" do
      limited_user = create(:copilot_limited_user, user: create(:user), subscribed_at: Time.now)
      limited_user.user = nil
      limited_user.save
      assert_equal Hash.new, limited_user.quotas_remaining
    end

    test "returns empty hash if subscribed_at is nil" do
      limited_user = create(:copilot_limited_user, user: create(:user), subscribed_at: nil)
      assert_equal Hash.new, limited_user.quotas_remaining
    end

    test "returns decremented hash only for feature that is used" do
      Copilot.redis.stubs(:hgetall).with(Copilot::LimitedUser::QUOTAS_KEY).returns({ "chat" => "50", "completions" => "2000" })
      feature = "chat"
      limited_user = create(:copilot_limited_user, user: create(:user), subscribed_at: Time.now)
      Copilot.redis.set(limited_user.feature_count_key(feature), "10")
      expected = {
        "chat" => 40, # this is how many they have left
        "completions" => 2000, # this is the monthly quota
      }
      assert_equal expected, limited_user.quotas_remaining
    end
  end

  context "quota_percentages_remaining" do
    test "returns empty hash if user is not present" do
      limited_user = create(:copilot_limited_user, user: create(:user), subscribed_at: Time.now)
      limited_user.user = nil
      limited_user.save
      assert_equal Hash.new, limited_user.quota_percentages_remaining
    end

    test "returns empty hash if subscribed_at is nil" do
      limited_user = create(:copilot_limited_user, user: create(:user), subscribed_at: nil)
      assert_equal Hash.new, limited_user.quota_percentages_remaining
    end

    test "returns decremented hash only for feature that is used" do
      Copilot.redis.stubs(:hgetall).with(Copilot::LimitedUser::QUOTAS_KEY).returns({ "chat" => "50", "completions" => "2000" })
      feature = "chat"
      limited_user = create(:copilot_limited_user, user: create(:user), subscribed_at: Time.now)
      Copilot.redis.set(limited_user.feature_count_key(feature), "10")
      expected = {
        "chat" => 80.0, # this is how many they have left
        "completions" => 100.0, # this is the monthly quota
      }
      assert_equal expected, limited_user.quota_percentages_remaining
    end
  end

  context "set_quota_remaining" do
    test "returns a Copilot::Result" do
      limited_user = create(:copilot_limited_user, user: create(:user), subscribed_at: Time.now)
      result = limited_user.set_quota_remaining(feature: "chat", quota: 10)
      assert_instance_of GitHub::Result, result
      assert result.ok?
    end

    test "returns a Copilot::Result with an error message if the user is not present" do
      limited_user = create(:copilot_limited_user, user: create(:user), subscribed_at: Time.now)
      limited_user.user = nil
      limited_user.save
      result = limited_user.set_quota_remaining(feature: "chat", quota: 10)
      assert_raises RuntimeError, "User missing" do
        result.value!
      end
      refute result.ok?
    end

    test "returns a Copilot::Result with an error message if the user is not subscribed" do
      limited_user = create(:copilot_limited_user, user: create(:user), subscribed_at: nil)
      result = limited_user.set_quota_remaining(feature: "chat", quota: 10)
      assert_raises RuntimeError, "User not subscribed" do
        result.value!
      end
      refute result.ok?
    end

    test "returns a Copilot::Result with an error message if the feature is not in ALLOWED_FEATURES" do
      limited_user = create(:copilot_limited_user, user: create(:user), subscribed_at: Time.now)
      result = limited_user.set_quota_remaining(feature: "foo", quota: 10)
      assert_raises RuntimeError, "Feature not allowed" do
        result.value!
      end
      refute result.ok?
    end

    test "returns a Copilot::Result with an error message if the quota is less than 0" do
      limited_user = create(:copilot_limited_user, user: create(:user), subscribed_at: Time.now)
      result = limited_user.set_quota_remaining(feature: "chat", quota: -1)
      assert_raises RuntimeError, "Quota must be greater than 0" do
        result.value!
      end
      refute result.ok?
    end

    test "returns a Copilot::Result with an error message if redis has an error" do
      limited_user = create(:copilot_limited_user, user: create(:user), subscribed_at: Time.now)
      Copilot.redis.stubs(:set).raises(Redis::BaseError)
      result = limited_user.set_quota_remaining(feature: "chat", quota: 10)
      assert_raises Redis::BaseError do
        result.value!
      end
      refute result.ok?
    end

    test "sets the quota in redis" do
      Copilot.redis.stubs(:hgetall).with(Copilot::LimitedUser::QUOTAS_KEY).returns({ "chat" => "50", "completions" => "2000" })
      limited_user = create(:copilot_limited_user, user: create(:user), subscribed_at: Time.now)
      limited_user.set_quota_remaining(feature: "chat", quota: 10)
      assert_equal 10, limited_user.feature_quota_remaining(feature: "chat")
    end
  end
end if GitHub.copilot_enabled?
