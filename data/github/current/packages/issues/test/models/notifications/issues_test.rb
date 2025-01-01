# typed: true
# frozen_string_literal: true

require "test_helpers/notifications/test_helper"

class NotificationsIssuesTest < GitHub::TestCase
  include Notifications::TestHelper
  extend ClassMethods

  shared_notification_tests!
  shared_mention_tests!

  fixtures do
    @owner, @author, @reader = create_users :owner, :author, :reader
    @org, @team = create_org @owner
    @list = create :private_repository, owner: @org, name: "repo"
    @team.add_repository(@list, :push)
    Organization.update_all plan: "free" # lets us mark author as spammy
    @visitor = create_users :visitor
  end

  setup do
    GitHub.flipper[:notifyd_issue_watch_activity_notify].disable
  end

  def trigger_notifications(options = {})
    create(:issue, options.reverse_merge(user: @author, repository: @list))
  end
end
