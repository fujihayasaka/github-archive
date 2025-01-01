# typed: true
# frozen_string_literal: true

require "test_helper"

class NotificationsContentTest < GitHub::TestCase

  test "SubscribeAndNotifyJob job is enqueued with deliver_notifications:false when send_notifications? is disabled" do
    issue = build(:issue)

    expected_args = [issue, {
      deliver_notifications: false,
      load_mentioned_users: true,
      load_mentioned_teams: true,
      author: issue.user,
      author_subscribe_reason: :author,
      subscriber_reasons_and_ids: nil,
    }]

    GitHub.stubs(:send_notifications?).returns(false)

    assert_enqueued_with(job: SubscribeAndNotifyJob, args: expected_args) do
      issue.save
    end
  end

  test "SubscribeAndNotifyJob job is enqueued with deliver_notifications:true when send_notifications? is enabled" do
    issue = build(:issue)

    expected_args = [issue, {
      deliver_notifications: true,
      load_mentioned_users: true,
      load_mentioned_teams: true,
      author: issue.user,
      author_subscribe_reason: :author,
      subscriber_reasons_and_ids: nil,
    }]

    GitHub.stubs(:send_notifications?).returns(true)

    assert_enqueued_with(job: SubscribeAndNotifyJob, args: expected_args) do
      issue.save
    end
  end

  test "UpdateSubscriptionsAndNotifyJob is enqueued with deliver_notifications:true when the body is changed" do
    issue = create(:issue)
    new_body = "new issue body"

    expected_args = [{
      deliver_notifications: true,
      subject: issue,
      previous_body: [issue.body, new_body]
    }]

    GitHub.stubs(:send_notifications?).returns(true)
    assert_enqueued_with(job: UpdateSubscriptionsAndNotifyJob, args: expected_args) do
      issue.update_attribute(:body, new_body)
    end
  end
end
