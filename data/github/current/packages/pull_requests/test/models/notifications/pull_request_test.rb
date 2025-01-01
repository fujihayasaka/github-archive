# typed: true
# frozen_string_literal: true

require "test_helpers/notifications/test_helper"

class NotificationsPullRequestsTest < GitHub::TestCase
  include Notifications::TestHelper
  include GitHub::PullRequestTestHelpers

  extend ClassMethods

  shared_notification_tests!
  shared_mention_tests!

  fixtures do
    @owner, @author, @reader = create_users :owner, :author, :reader
    @org, @team = create_org @owner
    @list = create :private_repository, owner: @org, name: "repo", from_example: :pull_request_bases
    @team.add_repository(@list, :push)
    Organization.update_all plan: "free" # lets us mark author as spammy
    @visitor = create_users :visitor
  end

  def trigger_notifications(options = {})
    pull = PullRequest.create_for @list, options.reverse_merge(
      base: "simple/master",
      head: "simple/branch",
      user: @author, title: "New PR", body: "OK")
    if pull.new_record?
      raise ActiveRecord::RecordInvalid.new(pull)
    end
    pull.issue
  end
end
