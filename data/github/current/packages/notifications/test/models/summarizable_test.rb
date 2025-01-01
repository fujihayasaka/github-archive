# typed: strict
# frozen_string_literal: true

require "test_helper"

class SummarizableTest < GitHub::TestCase
  include DogstatsTestHelpers

  test "records metrics on update_notification_summary method with correct subject type" do
    issue = create(:issue)
    NotificationSummary.new(list: issue.repository, thread: issue).summarize!(nil)
    assert issue.update_notification_summary(enqueue: false)
    assert_dogstats_distribution(1, "notifications.update_notification_rollup.latency", tags: ["subject_type:Issue", "status:succeeded"])

    discussion = create(:discussion)
    NotificationSummary.new(list: discussion.repository, thread: discussion).summarize!(nil)
    assert discussion.update_notification_summary(enqueue: false)
    assert_dogstats_distribution(1, "notifications.update_notification_rollup.latency", tags: ["subject_type:Discussion", "status:succeeded"])
  end

  test "records metrics on get_notification_summary failures" do
    failed_response = Newsies::Response.new { raise SystemCallError, "test" }

    Issue.any_instance.expects(:get_notification_summary).returns(failed_response)
    issue = create(:issue)

    refute issue.update_notification_summary(enqueue: false)
    assert_dogstats_distribution(1, "notifications.update_notification_rollup.latency", tags: ["subject_type:Issue", "status:failed_on_get_summary"])
  end

  test "records metrics when get_notification_summary is nil" do
    issue = create(:issue)
    NotificationSummary.new(list: issue.repository, thread: issue).summarize!(nil)

    failed_response = Newsies::Response.new { nil }
    failed_response.success = true
    Issue.any_instance.expects(:get_notification_summary).returns(failed_response)

    # We return true to keep previous behavior
    assert issue.update_notification_summary(enqueue: false)
    assert_dogstats_distribution(1, "notifications.update_notification_rollup.latency", tags: ["subject_type:Issue", "status:missing_summary"])
  end

  test "records metrics on update failures" do
    issue = create(:issue)
    NotificationSummary.new(list: issue.repository, thread: issue).save
    NotificationSummary.any_instance.expects(:save).raises(ActiveRecord::ConnectionNotEstablished.new)

    refute issue.update_notification_summary(enqueue: false)
    assert_dogstats_distribution(1, "notifications.update_notification_rollup.latency", tags: ["subject_type:Issue", "status:failed_on_save"])
  end
end
