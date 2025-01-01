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
    Copilot.limiter_redis.flushdb
  end

  context "subscribe_user" do
    test "returns success if limited user is already subscribed" do
      create(:copilot_limited_user, user: @user, subscribed_at: Time.now)

      result = Copilot::LimitedUser.subscribe_user(@user)
      assert result.ok?
    end

    test "returns error for an emu user" do
      user = create(:emu)

      result = Copilot::LimitedUser.subscribe_user(user)
      refute result.ok?
    end

    test "returns error if the user is spammy" do
      @user.update(spammy: true)
      result = Copilot::LimitedUser.subscribe_user(@user)
      refute result.ok?
    end

    test "returns error if the user has no validated emails" do
      user = create(:user)
      result = Copilot::LimitedUser.subscribe_user(user)
      refute result.ok?
    end

    test "returns error if the user already has free access" do
      free_user = create(:copilot_free_user)
      user = free_user.user
      result = Copilot::LimitedUser.subscribe_user(user)
      refute result.ok?
    end

    test "returns error if the user already has trial access" do
      copilot_monthly_product_uuid = create(:billing_product_uuid, :copilot, :monthly)
      plan_subscription = create(:billing_plan_subscription, :zuora)
      user = plan_subscription.user
      create(:billing_subscription_item, :paid,
        plan_subscription: plan_subscription,
        subscribable: copilot_monthly_product_uuid,
        free_trial_ends_on: 10.days.from_now
       )

      result = Copilot::LimitedUser.subscribe_user(user)
      refute result.ok?
    end

    test "returns error if the user already has paid access" do
      copilot_monthly_product_uuid = create(:billing_product_uuid, :copilot, :monthly)
      plan_subscription = create(:billing_plan_subscription, :zuora)
      user = plan_subscription.user
      create(:billing_subscription_item, :paid,
        plan_subscription: plan_subscription,
        subscribable: copilot_monthly_product_uuid,
       )

      result = Copilot::LimitedUser.subscribe_user(user)
      refute result.ok?
    end

    test "returns error if the already has cfb access" do
      seat = create(:copilot_seat)
      user = seat.assigned_user
      user.emails.map(&:verify!)

      assert Copilot::User.new(user).has_cfb_access?

      result = Copilot::LimitedUser.subscribe_user(user)
      refute result.ok?
    end

    test "returns success if the user already has a subscribed record" do
      seq = sequence("test")
      Copilot::LimitedUser.expects(:for_subscribed_user).with(@user).in_sequence(seq).returns(nil)
      Copilot::LimitedUser.expects(:for_subscribed_user).with(@user).in_sequence(seq).returns(create(:copilot_limited_user, user: @user, subscribed_at: Time.now))
      @user.emails.map(&:verify!)

      result = Copilot::LimitedUser.subscribe_user(@user)
      assert result.ok?
    end

    test "returns success if the user has an unsubscribed record" do
      create(:copilot_limited_user, user: @user, subscribed_at: nil)
      @user.emails.map(&:verify!)

      result = Copilot::LimitedUser.subscribe_user(@user)
      assert result.ok?

      assert Copilot::LimitedUser.for_subscribed_user(@user).present?
    end

    test "creates a new record and subscribes it" do
      @user.emails.map(&:verify!)
      result = Copilot::LimitedUser.subscribe_user(@user)
      assert result.ok?

      assert Copilot::LimitedUser.for_subscribed_user(@user).present?
    end

    test "returns error if the user already has an unsubscribed record and we get an error" do
      create(:copilot_limited_user, user: @user, subscribed_at: nil)
      @user.emails.map(&:verify!)
      Copilot::LimitedUser.any_instance.stubs(:update).raises(Trilogy::BaseError.new("ldfksajlkj")) #rubocop:disable GitHub/DoNotReferenceTrilogy

      result = Copilot::LimitedUser.subscribe_user(@user)
      refute result.ok?
      refute Copilot::LimitedUser.for_subscribed_user(@user).present?
    end

    test "returns error if we can't create the new record" do
      @user.emails.map(&:verify!)

      Copilot::LimitedUser.stubs(:create).raises(Trilogy::BaseError.new("ldfksajlkj")) #rubocop:disable GitHub/DoNotReferenceTrilogy
      result = Copilot::LimitedUser.subscribe_user(@user)
      refute result.ok?

      refute Copilot::LimitedUser.for_subscribed_user(@user).present?
    end

    test "sets subscribed_at to Time.now" do
      travel_to Time.new(2022, 1, 1) do
        @user.emails.map(&:verify!)
        result = Copilot::LimitedUser.subscribe_user(@user)
        assert result.ok?

        limited_user = Copilot::LimitedUser.for_subscribed_user(@user)
        assert limited_user.present?
        assert_equal T.must(limited_user).subscribed_at, Time.new(2022, 1, 1)
      end
    end

    test "sends subscription email" do
      mailer = mock
      mailer.stubs(:deliver_later)

      CopilotLimitedUserMailer.expects(:subscribe).returns(mailer).once
      @user.emails.map(&:verify!)

      result = Copilot::LimitedUser.subscribe_user(@user)
      assert result.ok?
    end
  end

  context "subscribed?" do
    test "returns false if subscribed_at is nil" do
      limited_user = create(:copilot_limited_user, user: create(:user), subscribed_at: nil)
      refute limited_user.subscribed?
    end

    test "returns true if subscribed_at is set" do
      limited_user = create(:copilot_limited_user, user: create(:user), subscribed_at: Time.now)
      assert limited_user.subscribed?
    end
  end

  # ruby is normally awesome but it doesn't do a great job of giving us NEXT month's date in a way that handles real months
  #
  # when going from dates up to 28, we should just work as expected
  #
  # here are the concerning cases:
  #
  # Jan 29,30,31 -> Feb 28/29 non/leap year
  # Feb 28,29    -> Mar 28/29 non/leap year
  # Mar 31       -> Apr 30
  # Apr 30       -> May 30
  # May 31       -> Jun 30
  # Jun 30       -> Jul 30
  # Jul 31       -> Aug 31
  # Aug 31       -> Sep 30
  # Sep 30       -> Oct 30
  # Oct 31       -> Nov 30
  # Nov 30       -> Dec 30
  context "reset_date" do
    test "returns nil if subcribed_at is nil" do
      limited_user = create(:copilot_limited_user, user: create(:user), subscribed_at: nil)
      refute_nil limited_user.reset_date
      assert_equal Date.new, limited_user.reset_date
    end

    [
      { today: Time.new(2022, 1, 29), expected: Date.new(2022, 2, 28) },
      { today: Time.new(2022, 1, 30), expected: Date.new(2022, 2, 28) },
      { today: Time.new(2022, 1, 31), expected: Date.new(2022, 2, 28) },
      { today: Time.new(2020, 1, 29), expected: Date.new(2020, 2, 29) },
      { today: Time.new(2020, 1, 30), expected: Date.new(2020, 2, 29) },
      { today: Time.new(2020, 1, 31), expected: Date.new(2020, 2, 29) },
      { today: Time.new(2022, 2, 28), expected: Date.new(2022, 3, 28) },
      { today: Time.new(2020, 2, 29), expected: Date.new(2020, 3, 29) },
      { today: Time.new(2022, 3, 31), expected: Date.new(2022, 4, 30) },
      { today: Time.new(2022, 4, 30), expected: Date.new(2022, 5, 30) },
      { today: Time.new(2022, 5, 31), expected: Date.new(2022, 6, 30) },
      { today: Time.new(2022, 6, 30), expected: Date.new(2022, 7, 30) },
      { today: Time.new(2022, 7, 31), expected: Date.new(2022, 8, 31) },
      { today: Time.new(2022, 8, 31), expected: Date.new(2022, 9, 30) },
      { today: Time.new(2022, 9, 30), expected: Date.new(2022, 10, 30) },
      { today: Time.new(2022, 10, 31), expected: Date.new(2022, 11, 30) },
      { today: Time.new(2022, 11, 30), expected: Date.new(2022, 12, 30) },
      { today: Time.new(2022, 12, 31), expected: Date.new(2023, 1, 31) },
    ].each do |test_case|
      test "returns #{test_case[:expected]} if subcribed_at is set and today is #{test_case[:today]}" do
        travel_to test_case[:today] do
          limited_user = create(:copilot_limited_user, user: create(:user), subscribed_at: Time.now)
          limited_user.reload
          assert_equal limited_user.subscribed_at, Time.now

          assert_equal test_case[:expected], limited_user.reset_date
          chat_key = "chat:#{limited_user.user.analytics_tracking_id}"
          assert_equal chat_key, limited_user.feature_count_key("chat")
        end
      end
    end

    test "returns next month if subcribed_at is set" do
      travel_to Time.new(2022, 1, 1) do
        limited_user = create(:copilot_limited_user, user: create(:user), subscribed_at: Time.new(2022, 1, 1))
        limited_user.reload
        assert_equal limited_user.subscribed_at, Time.new(2022, 1, 1)
        assert_equal Date.new(2022, 2, 1), limited_user.reset_date
      end
    end

    test "handles leap day -> next year" do
      travel_to Time.new(2021, 1, 31) do
        leap_day = Time.new(2020, 2, 29)
        limited_user = create(:copilot_limited_user, user: create(:user), subscribed_at: leap_day)
        limited_user.reload
        assert_equal limited_user.subscribed_at, leap_day
        assert_equal Date.new(2021, 2, 28), limited_user.reset_date
      end
    end

    test "handle rollover of month" do
      travel_to Time.new(2022, 1, 2) do
        limited_user = create(:copilot_limited_user, user: create(:user), subscribed_at: Time.new(2021, 12, 19))
        limited_user.reload
        assert_equal limited_user.subscribed_at, Time.new(2021, 12, 19)
        assert_equal Date.new(2022, 1, 19), limited_user.reset_date
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
      feature = "chat"
      limited_user = create(:copilot_limited_user, user: create(:user), subscribed_at: Time.now)
      limited_user.set_quota_remaining(feature: feature, quota: 10)
      assert limited_user.feature_allowed?(feature: feature)
    end
  end

  context "feature_quota_remaining" do
    test "returns 0 if user is not present" do
      limited_user = create(:copilot_limited_user, user: create(:user), subscribed_at: Time.now)
      limited_user.user = nil
      limited_user.save
      assert_equal 0, limited_user.feature_quota_remaining(feature: "chat")
    end

    test "returns 0 if subscribed_at is nil" do
      limited_user = create(:copilot_limited_user, user: create(:user), subscribed_at: nil)
      assert_equal 0, limited_user.feature_quota_remaining(feature: "chat")
    end

    test "returns 0 if feature is not in ALLOWED_FEATURES" do
      limited_user = create(:copilot_limited_user, user: create(:user), subscribed_at: Time.now)
      assert_equal 0, limited_user.feature_quota_remaining(feature: "foo")
    end

    test "returns the monthly quota amount if the key is empty" do
      feature = "chat"
      limited_user = create(:copilot_limited_user, user: create(:user), subscribed_at: Time.now)
      assert_equal 500, limited_user.feature_quota_remaining(feature: feature)
    end

    test "returns 10 if the key is 10" do
      feature = "chat"
      limited_user = create(:copilot_limited_user, user: create(:user), subscribed_at: Time.now)
      Copilot.limiter_redis.set(limited_user.feature_count_key(feature), "10")
      assert_equal 490, limited_user.feature_quota_remaining(feature: feature)
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
      feature = "chat"
      limited_user = create(:copilot_limited_user, user: create(:user), subscribed_at: Time.now)
      assert_equal 100.0, limited_user.feature_quota_percentage_remaining(feature: feature)
    end

    test "returns 80.0 if the user has 1/5 used" do
      feature = "chat"
      limited_user = create(:copilot_limited_user, user: create(:user), subscribed_at: Time.now)
      Copilot.limiter_redis.set(limited_user.feature_count_key(feature), "100")
      assert_equal 80.0, limited_user.feature_quota_percentage_remaining(feature: feature)
    end

    test "returns 60.0 if the user has 2/5 used" do
      feature = "chat"
      limited_user = create(:copilot_limited_user, user: create(:user), subscribed_at: Time.now)
      Copilot.limiter_redis.set(limited_user.feature_count_key(feature), "200")
      assert_equal 60.0, limited_user.feature_quota_percentage_remaining(feature: feature)
    end

    test "returns 40.0 if the user has 3/5 used" do
      feature = "chat"
      limited_user = create(:copilot_limited_user, user: create(:user), subscribed_at: Time.now)
      Copilot.limiter_redis.set(limited_user.feature_count_key(feature), "300")
      assert_equal 40.0, limited_user.feature_quota_percentage_remaining(feature: feature)
    end

    test "returns 20.0 if the user has 4/5 used" do
      feature = "chat"
      limited_user = create(:copilot_limited_user, user: create(:user), subscribed_at: Time.now)
      Copilot.limiter_redis.set(limited_user.feature_count_key(feature), "400")
      assert_equal 20.0, limited_user.feature_quota_percentage_remaining(feature: feature)
    end

    test "returns 0.0 if the user has 5/5 used" do
      feature = "chat"
      limited_user = create(:copilot_limited_user, user: create(:user), subscribed_at: Time.now)
      Copilot.limiter_redis.set(limited_user.feature_count_key(feature), "500")
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
      feature = "chat"
      limited_user = create(:copilot_limited_user, user: create(:user), subscribed_at: Time.now)
      Copilot.limiter_redis.set(limited_user.feature_count_key(feature), "10")
      expected = {
        "chat" => 490, # this is how many they have left
        "completions" => 2000, # this is the monthly quota
      }
      assert_equal expected, limited_user.quotas_remaining
    end

    test "doesn't let us get negative about ourselves" do
      feature = "chat"
      limited_user = create(:copilot_limited_user, user: create(:user), subscribed_at: Time.now)
      Copilot.limiter_redis.set(limited_user.feature_count_key(feature), "600")
      expected = {
        "chat" => 0, # this is how many they have left
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
      feature = "chat"
      limited_user = create(:copilot_limited_user, user: create(:user), subscribed_at: Time.now)
      Copilot.limiter_redis.set(limited_user.feature_count_key(feature), "100")
      expected = {
        "chat" => 80.0, # this is how many they have left (10/50)
        "completions" => 100.0, # this is the monthly quota (2000/2000)
      }
      assert_equal expected, limited_user.quota_percentages_remaining
    end

    test "is always positive about us" do
      feature = "chat"
      limited_user = create(:copilot_limited_user, user: create(:user), subscribed_at: Time.now)
      Copilot.limiter_redis.set(limited_user.feature_count_key(feature), "600")
      expected = {
        "chat" => 0.0, # this is how many they have left (0/50) - technically -10 but we don't show negative values
        "completions" => 100.0, # this is the monthly quota (2000/2000)
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
      Copilot.limiter_redis.stubs(:set).raises(Redis::BaseError)
      result = limited_user.set_quota_remaining(feature: "chat", quota: 10)
      assert_raises RuntimeError do
        result.value!
      end
      refute result.ok?
    end

    test "sets the quota in redis" do
      limited_user = create(:copilot_limited_user, user: create(:user), subscribed_at: Time.now)
      limited_user.set_quota_remaining(feature: "chat", quota: 10)
      assert_equal 10, limited_user.feature_quota_remaining(feature: "chat")
    end
  end
end if GitHub.copilot_enabled?
