# typed: true
# frozen_string_literal: true

require "test_helper"

class MobilePushNotificationSettingTest < GitHub::TestCase
  fixtures do
    @user = create(:user)

    Notifyd::MobilePushSettingsStore.any_instance.stubs(:get).returns(Notifyd::MobilePushSettings.default)
    Notifyd::MobilePushSettingsStore.any_instance.stubs(:save).returns(true)
    @setting = create(:mobile_push_notification_setting, user: @user)
  end

  test "gets user mention push settings" do
    refute @setting.direct_mentions?
    @setting.direct_mention = true
    assert @setting.direct_mentions?
    @setting.direct_mention = false
    refute @setting.direct_mentions?
  end

  test "gets user assignment push settings" do
    refute @setting.assignments?
    @setting.assignment = true
    assert @setting.assignments?
    @setting.assignment = false
    refute @setting.assignments?
  end

  test "gets user review request push settings" do
    refute @setting.review_requests?
    @setting.review_requested = true
    assert @setting.review_requests?
    @setting.review_requested = false
    refute @setting.review_requests?
  end

  test "gets user deployment request push settings" do
    refute @setting.deployment_requests?
    @setting.deployment_request = true
    assert @setting.deployment_requests?
    @setting.deployment_request = false
    refute @setting.deployment_requests?
  end

  test "gets user scheduled push notification enabled" do
    refute @setting.scheduled_notifications?
    @setting.scheduled_notifications = true
    assert @setting.scheduled_notifications?
    @setting.scheduled_notifications = false
    refute @setting.scheduled_notifications?
  end

  test "gets user pull request review enabled" do
    refute @setting.pull_request_reviews?
    @setting.pull_request_review = true
    assert @setting.pull_request_reviews?
    @setting.pull_request_review = false
    refute @setting.pull_request_reviews?
  end
end
