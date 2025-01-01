# typed: true
# frozen_string_literal: true

require "test_helpers/notifications/test_helper"

class NotificationsReleasesTest < GitHub::TestCase
  include Notifications::TestHelper
  T.unsafe(self).shared_notification_tests!

  fixtures do
    @owner, @author, @reader = create_users :owner, :author, :reader
    @org, @team = create_org @owner
    @list = create :private_repository, owner: @org, name: "repo", from_example: :repository_test_simple
    @team.add_repository(@list, :push)
    Organization.update_all plan: "free" # lets us mark author as spammy
    @visitor = create_users :visitor
  end

  def trigger_notifications(options = {})
    create :release, options.reverse_merge(
      tag_name: "v1", author: @author, repository: @list, draft: false)
  end

  # Author is not subscribed to the Release because Releases have no comments.
  # No point in subscribing users.  Only repository watchers get notifications.
  def default_subscribed
    {}
  end
end
