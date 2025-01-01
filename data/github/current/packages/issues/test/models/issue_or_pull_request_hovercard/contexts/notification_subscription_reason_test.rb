# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/notifications/notifyd_test_helper"

class IssueOrPullRequestHovercardContextsNotificationSubscriptionReasonTest < GitHub::TestCase
  include Notifications::NotifydTestHelper

  fixtures do
    @collaborator = create(:user)
    @repo = create(:repository)
    @repo.add_member(@collaborator)
  end

  def async_resolve(*args, **kwargs)
    T.unsafe(IssueOrPullRequestHovercard::Contexts::NotificationSubscriptionReason).async_resolve(*args, **kwargs)
  end

  context ".async_resolve" do
    test "returns a context with a message when viewer is subscribed to a thread" do
      viewer = @collaborator
      issue = create(:issue, repository: @repo)
      GitHub.newsies.subscribe_to_thread(viewer, @repo, issue, "manual")

      # All features will run this test with notifyd enabled, so we need to stub
      stub_notifyd(subscription_type: :thread, user: viewer, list: @repo, thread: issue) if issue.notifyd_primary?(viewer)

      context = async_resolve(issue_or_pull_request: issue, viewer: viewer).sync

      refute_nil context
      assert_equal "You’re receiving notifications because you’re subscribed to this thread.", context.message
    end

    test "returns a context with a message indicating viewer is watching repo when that is reason viewer is seeing notice" do
      non_collaborator = create(:user)
      non_collaborator.watch_repo(@repo)
      issue = create(:issue, repository: @repo, assignee: @collaborator)

      # All features will run this test with notifyd enabled, so we need to stub
      stub_notifyd(subscription_type: :list, user: non_collaborator, list: @repo, thread: issue) if issue.notifyd_primary?(non_collaborator)

      context = async_resolve(issue_or_pull_request: issue, viewer: non_collaborator).sync

      refute_nil context
      assert_equal "You’re receiving notifications because you’re watching this repository.", context.message
    end

    test "returns a context with a message when viewer is subscribed via pr review request" do
      requested_reviewer = create(:user)
      pr = create(:pull_request, :disable_disk_access, repository: @repo)
      pr.repository.add_member(requested_reviewer)
      perform_enqueued_jobs(only: SubscribeAndNotifyJob) { create(:review_request, pull_request: pr, reviewer: requested_reviewer) }

      context = async_resolve(issue_or_pull_request: pr, viewer: requested_reviewer).sync

      refute_nil context
      assert_equal "You’re receiving notifications because your review was requested.", context.message
    end

    test "returns a nil context when viewer is not subscribed to a thread or watching a repo" do
      non_collaborator = create(:user)
      issue = create(:issue, repository: @repo, assignee: @collaborator)

      # All features will run this test with notifyd enabled, so we need to stub
      stub_notifyd if issue.notifyd_primary?(non_collaborator)

      context = async_resolve(issue_or_pull_request: issue, viewer: non_collaborator).sync

      assert_nil context
    end
  end
end
