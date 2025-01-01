# typed: true
# frozen_string_literal: true

require "test_helper"

class UserMobileDependencyTest < GitHub::TestCase
  include DogstatsTestHelpers

  fixtures do
    make_trusted_oauth_apps_owner
    @user = create(:user)
    @ios_app = create(:github_mobile_oauth_app)
    @android_app = create(:github_mobile_android_oauth_app)
  end

  context "#uses_mobile_app?" do
    test "is false with no apps" do
      refute_predicate @user, :uses_mobile_app?
    end

    test "is true with an ios app" do
      make_oauth(@user, %w[user notifications repo], @ios_app)
      assert_predicate @user, :uses_mobile_app?
    end

    test "is true with an android app" do
      make_oauth(@user, %w[user notifications repo], @android_app)
      assert_predicate @user, :uses_mobile_app?
    end

    test "logs dogstats metrics" do
      @user.uses_mobile_app?
      assert_dogstats_distribution(1, "user.uses_mobile_app")
    end
  end

  context "#has_mobile_app_activity?" do
    test "is false when the user has not used the app" do
      refute @user.has_mobile_app_activity?(nil)
    end

    test "is false when the user has the app but has not used it" do
      make_oauth(@user, %w[user notifications repo], @ios_app)
      refute @user.has_mobile_app_activity?(nil)
    end

    test "user uses the app within the timeframe, and does not open the app for 6 months" do
      oauth_access = make_oauth(@user, %w[user notifications repo], @ios_app)
      now = Time.now.beginning_of_day
      Timecop.freeze(now) do
        oauth_access.bump!(now)
        six_months = 6.months
        # before the travel, the user has used the app within the timeframe
        assert @user.has_mobile_app_activity?(six_months.ago)
        Timecop.travel(six_months)
        # after the travel, the user has used the app outside the timeframe where its passed the given timeframe
        refute @user.has_mobile_app_activity?(now)
      end
    end

    test "logs dogstats metrics" do
      @user.has_mobile_app_activity?(Time.now)
      assert_dogstats_distribution(1, "user.has_mobile_app_activity")
    end
  end
end
