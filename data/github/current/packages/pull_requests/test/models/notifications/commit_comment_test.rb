# typed: true
# frozen_string_literal: true

require "test_helpers/notifications/test_helper"

class NotificationsCommitCommentsTest < GitHub::TestCase
  include Notifications::TestHelper
  extend Notifications::TestHelper::ClassMethods

  shared_notification_tests!
  shared_mention_tests!

  fixtures do
    @owner, @reader = create_users :owner, :reader
    @author = create :user, login: "author", email: "technoweenie@gmail.com"
    @org, @team = create_org @owner
    @list = create :private_repository, owner: @org, name: "repo", from_example: :commit_comments
    @team.add_repository(@list, :push)
    Organization.update_all plan: "free" # lets us mark author as spammy
    @commit_oid = "c3956841a7cb7e8ba4a6fd923568d86958f01573"
    @visitor = create_users :visitor
  end

  def trigger_notifications(options = {})
    create(:commit_comment, options.reverse_merge(
      user: @author, repository: @list, commit_id: @commit_oid, created_at: Time.now)
    )
  end

  # Commit Comments have no clear "thread" object, or "conversation subject"
  # So, the author gets subscribed with a reason of "comment" instead of "author".
  def default_subscribed
    { @author => :comment }
  end
end
