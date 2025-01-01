# typed: true
# frozen_string_literal: true

require "test_helper"

class UnsubscribeFromLinkTest < GitHub::TestCase
  include GitHub::LoggerHelper

  test "for a newsies token" do
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

  test "for a notifyd token" do
    user = create(:user)
    gist = create(:gist)
    payload = {
      subject_type: "gist",
      topics: [{ type: "gist", value: gist.id.to_s }],
    }
    action = :mute_list
    token = Notifyd::UnsubscribeToken.new(action).sign(user, payload)

    unsubscribe = UnsubscribeFromLink.new(action, token)
    auth, resource = unsubscribe.prepare

    assert_predicate auth, :valid?
    assert auth.for_user?(user)
    assert_equal user, auth.user
    assert_predicate auth.result, :success?
    assert_equal gist, resource.thread
    assert_predicate resource, :valid?
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

  test "logs are emitted" do
    action = :mute_list
    user = create(:user)
    repo = create(:repository)
    GitHub.newsies.subscribe_to_list(user, repo)
    issue = perform_enqueued_jobs(only: [SubscribeAndNotifyJob, Newsies::DeliverNotificationsJob]) do
      create(:issue, repository: repo, user: user).tap(&:deliver_notifications)
    end
    summary = NotificationSummary.by_thread(repo, issue)
    token   = GitHub.newsies.token action, user, summary[:id]

    expected_log = {
      "Body" => "unsubscribe_from_link",
      "code.namespace" => "UnsubscribeFromLink",
      "code.function" => "prepare",
      "gh.catalog_service" => "github/notifications",
      "gh.notifications.action" => action,
      "gh.notifications.service" => :newsies,
      "gh.notifications.thread.type" => "Issue",
      "gh.notifications.thread.id" => issue.id
    }

    assert_logged(**expected_log) do
      unsubscribe = UnsubscribeFromLink.new(action, token)
      unsubscribe.prepare
    end
  end

  context "unsubscribe" do
    test "changes the subscription status for newsies" do
      action = :mute_list
      user = create(:user)
      repo = create(:repository)
      GitHub.newsies.subscribe_to_list(user, repo)
      issue = perform_enqueued_jobs(only: [SubscribeAndNotifyJob, Newsies::DeliverNotificationsJob]) do
        create(:issue, repository: repo, user: user).tap(&:deliver_notifications)
      end
      summary = NotificationSummary.by_thread(repo, issue)
      token   = GitHub.newsies.token action, user, summary[:id]

      assert_changes -> { GitHub.newsies.subscription_status(user, repo, issue).ignored? }, from: false, to: true do
        unsubscribe = UnsubscribeFromLink.new(action, token)
        unsubscribe.unsubscribe
      end
    end
  end
end
