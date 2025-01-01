# typed: true
# frozen_string_literal: true

require "test_helpers/notifications/test_helper"

class NotificationsIssueCommentsTest < GitHub::TestCase
  include Notifications::TestHelper
  extend ClassMethods

  shared_notification_tests!
  shared_mention_tests!

  fixtures do
    @owner, @author, @thread_author, @reader = create_users :owner, :author, :threadauthor, :reader
    @org, @team = create_org @owner
    @list = create :private_repository, owner: @org, name: "repo"
    @team.add_repository(@list, :push)
    @thread = create :issue, :subscribed_author, user: @thread_author, repository: @list
    Organization.update_all plan: "free" # lets us mark author as spammy
    @visitor = create_users :visitor
  end

  setup do
    disable_feature_flag(:notifyd_issue_watch_activity_notify)
  end

  def trigger_notifications(options = {})
    create :issue_comment, options.reverse_merge(issue: @thread, user: @author)
  end
end
