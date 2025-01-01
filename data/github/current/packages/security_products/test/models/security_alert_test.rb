# typed: true
# frozen_string_literal: true

require "test_helper"

class SecurityAlertTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @repo = create(:repository, owner: @user)
  end

  context ".user_ids_subscribed_to_security_alerts" do
    test "excludes users who aren't watching the repository or subscribed to the thread type", skip_enterprise: true do
      assert_equal true, @user.unwatch_repo(@repo)
      assert_empty SecurityAlert.user_ids_subscribed_to_security_alerts(@repo, [@user.id])

      assert_equal true, @user.subscribe_to_thread_types(@repo, [Issue])
      assert_empty SecurityAlert.user_ids_subscribed_to_security_alerts(@repo, [@user.id])
    end

    test "excludes users ignoring the repository" do
      assert_equal true, @user.ignore_repo(@repo)
      assert_empty SecurityAlert.user_ids_subscribed_to_security_alerts(@repo, [@user.id])
    end

    test "includes users watching the repository" do
      assert_equal true, @user.watch_repo(@repo)
      assert_equal [@user.id], SecurityAlert.user_ids_subscribed_to_security_alerts(@repo, [@user.id])
    end

    test "includes users subscribe to security alert thread types" do
      assert_equal true, @user.subscribe_to_thread_types(@repo, [SecurityAlert])
      assert_equal [@user.id], SecurityAlert.user_ids_subscribed_to_security_alerts(@repo, [@user.id])
    end
  end
end
