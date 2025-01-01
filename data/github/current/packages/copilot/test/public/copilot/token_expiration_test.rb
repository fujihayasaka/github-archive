# typed: true
# frozen_string_literal: true

require "test_helper"

class Copilot::TokenExpirationTest < GitHub::TestCase
  include CopilotTestHelper # automatically disables Copilot feature flags

  setup do
    disable_feature_flag(:copilot_free_token_refresh)
    Copilot::LimitedUser.destroy_all
  end

  test "nothing is set if the user is not in the feature flag" do
    user = create(:user)
    copilot_user = Copilot::User.new(user)

    logs = capture_logs do
      token_expiration = Copilot::TokenExpiration.new(copilot_user)
      assert_equal Copilot::TokenExpiration::TOKEN_EXPIRATION_SECONDS, token_expiration.token_expiration
    end

    assert_includes logs, "Feature flag not enabled, using defaults"
  end

  test "we get the defaults if we don't pass in a quota" do
    enable_feature_flag(:copilot_free_token_refresh)

    limited_user = create(:copilot_limited_user)
    user = limited_user.user

    Copilot::User.any_instance.stubs(:has_limited_access?).returns(true)
    copilot_user = Copilot::User.new(user)

    logs = capture_logs do
      token_expiration = Copilot::TokenExpiration.new(copilot_user)
      assert_equal Copilot::TokenExpiration::TOKEN_EXPIRATION_SECONDS, token_expiration.token_expiration
    end

    assert_includes logs, "Quota is full, using defaults"
  end

  test "we get the defaults if we pass in a 100% quota" do
    enable_feature_flag(:copilot_free_token_refresh)

    limited_user = create(:copilot_limited_user)
    user = limited_user.user

    Copilot::User.any_instance.stubs(:has_limited_access?).returns(true)
    copilot_user = Copilot::User.new(user)

    logs = capture_logs do
      token_expiration = Copilot::TokenExpiration.new(copilot_user, quota_remaining_percentage: 100.0)
      assert_equal Copilot::TokenExpiration::TOKEN_EXPIRATION_SECONDS, token_expiration.token_expiration
    end

    assert_includes logs, "Quota is full, using defaults"
  end

  test "nothing is set if the user is not a limited user" do
    enable_feature_flag(:copilot_free_token_refresh)

    user = create(:user)
    copilot_user = Copilot::User.new(user)

    logs = capture_logs do
      token_expiration = Copilot::TokenExpiration.new(copilot_user, quota_remaining_percentage: 50.0)
      assert_equal Copilot::TokenExpiration::TOKEN_EXPIRATION_SECONDS, token_expiration.token_expiration
    end

    assert_includes logs, "User does not have a subscribed limited user record, using defaults"
  end

  test "nothing is set if the limited user isn't subscribed" do
    enable_feature_flag(:copilot_free_token_refresh)

    limited_user = create(:copilot_limited_user, subscribed_at: nil)
    user = limited_user.user

    Copilot::User.any_instance.stubs(:has_limited_access?).returns(true)
    copilot_user = Copilot::User.new(user)

    logs = capture_logs do
      token_expiration = Copilot::TokenExpiration.new(copilot_user, quota_remaining_percentage: 50.0)
      assert_equal Copilot::TokenExpiration::TOKEN_EXPIRATION_SECONDS, token_expiration.token_expiration
    end

    assert_includes logs, "User does not have a subscribed limited user record, using defaults"
  end

  Copilot::TokenExpiration::TOKEN_EXPIRATION_DEFAULTS.each_with_index do |step, i|
    test "we get the correct token expiration for step #{i}" do
      enable_feature_flag(:copilot_free_token_refresh)

      limited_user = create(:copilot_limited_user)
      user = limited_user.user

      Copilot::User.any_instance.stubs(:has_limited_access?).returns(true)
      copilot_user = Copilot::User.new(user)

      token_expiration = Copilot::TokenExpiration.new(copilot_user, quota_remaining_percentage: step[:low].to_f)
      assert_equal step[:duration].to_i, token_expiration.token_expiration
    end
  end
end if GitHub.copilot_enabled?
