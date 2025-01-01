# typed: true
# frozen_string_literal: true

require "test_helper"

module Newsies
  class UnsubscribeFromLinkTest < GitHub::TestCase
    test "with a valid token" do
      action = :mute_list
      user = create(:user)
      repo = create(:repository)
      GitHub.newsies.subscribe_to_list(user, repo)
      issue = perform_enqueued_jobs(only: [SubscribeAndNotifyJob, Newsies::DeliverNotificationsJob]) do
        create(:issue, repository: repo, user: user).tap(&:deliver_notifications)
      end
      summary = NotificationSummary.by_thread(repo, issue)
      token   = GitHub.newsies.token action, user, summary[:id]

      unsubscribe = UnsubscribeFromLink.new(action, token)
      auth, resource = unsubscribe.prepare

      assert_predicate auth, :valid?
      assert auth.for_user?(user)
      assert_equal user, auth.user
      assert_predicate auth.result, :success?
      assert_equal issue, resource.thread
      assert_predicate resource, :valid?
      refute_nil resource.permalink
    end

    test "finds an issue that has transfered without any rollup summaries", skip_if_feature_disabled: :newsies_unsubscribe_follow_transfers do
      action = :mute_list
      user = create(:user)
      old_repository = create(:repository, owner: user)
      GitHub.newsies.subscribe_to_list(user, old_repository)

      issue = perform_enqueued_jobs(only: [SubscribeAndNotifyJob, Newsies::DeliverNotificationsJob]) do
        create(:issue, repository: old_repository, user: user).tap(&:deliver_notifications)
      end

      summary = NotificationSummary.by_thread(old_repository, issue)
      token = GitHub.newsies.token action, user, summary[:id], { thread_key: Thread.to_object(issue).key }

      new_repository = create(:repository, owner: user)
      transfer = IssueTransfer.new(old_issue: issue, old_repository: old_repository, new_repository: new_repository, actor: user)
      transfer.transfer!
      transfer.save!
      summary.destroy!

      unsubscribe = UnsubscribeFromLink.new(action, token)
      auth, resource = unsubscribe.prepare

      assert_predicate auth, :valid?
      assert auth.for_user?(user)
      assert_equal user, auth.user
      assert_predicate auth.result, :success?
      assert_equal issue.title, resource.thread.title
      refute_nil resource.permalink
    end

    test "for an invalid token" do
      action = :mute_list
      token = "foo"
      unsubscribe = UnsubscribeFromLink.new(action, token)
      auth, resource = unsubscribe.prepare

      refute_predicate auth, :valid?
      refute auth.for_user?(User.new)
      assert_nil auth.login
      assert_nil auth.user
      assert_nil resource.permalink
      assert_nil resource.thread
      refute_predicate resource, :valid?

      # NOTE: this has to be true becaues it asserts on the availability of the
      # DB cluster, not on the content of the result.
      assert_predicate auth.result, :success?
    end
  end
end
