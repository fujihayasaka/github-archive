# typed: true
# frozen_string_literal: true

require "test_helper"

class UserIndicatorModeTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @repo = create(:repository)
    @owner = @repo.owner

    GitHub.newsies.subscribe_to_list(@user, @repo)
    GitHub.newsies.get_and_update_settings(@user) do |settings|
      settings.participating_settings.clear
      settings.subscribed_settings.replace(%w(web))
    end
  end

  def test_user_without_notifications
    assert_equal :none, @user.indicator_mode
  end

  def test_user_with_global_notifications
    GitHub.flipper[:notifyd_issue_watch_activity_notify].disable
    other_repo = create(:repository, owner: @owner)
    GitHub.newsies.subscribe_to_list(@user, other_repo)
    notifications_for other_repo

    assert_equal :global, @user.indicator_mode
  end

  def test_user_with_vuln_enabled
    @user.disable_all_notifications
    GitHub.newsies.get_and_update_settings(@user) do |settings|
      settings.vulnerability_web = true
    end

    assert GitHub.newsies.settings(@user).settings_enabled_for?(:web)

    assert_equal :none, @user.indicator_mode
  end

  def test_user_with_web_disabled
    @user.disable_all_notifications
    refute GitHub.newsies.settings(@user).settings_enabled_for?(:web)

    assert_equal :disabled, @user.indicator_mode
  end

  def notifications_for(repository)
    only = [Newsies::DeliverNotificationsJob, SubscribeAndNotifyJob]
    perform_enqueued_jobs(only: only) do
      create :issue, user: @owner, repository: repository
    end
  end
end
