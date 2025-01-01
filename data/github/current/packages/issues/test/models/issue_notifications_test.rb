# typed: true
# frozen_string_literal: true

require "test_helper"

class IssueNotificationsTest < GitHub::TestCase
  include NewsiesHelper

  fixtures do
    # The fixtures block appears to run before the setup block, so even though
    # these lines are there we need them here too.
    @owner = create :user, :verified, login: "owner"
    @user = create :user, :verified, login: "user"
    @user2 = create :user, :verified, login: "user2"

    enable_notifications_for_user(@owner)
    enable_notifications_for_user(@user)
    enable_notifications_for_user(@user2)

    @repo = create :repository, owner: @owner
    @repo.add_member @user

    only = [SubscribeAndNotifyJob]
    @mentioned_issue = perform_enqueued_jobs(only: only) do
      create :issue, repository: @repo, user: @owner, body: "hi @user"
    end

    @org = create(:organization)
    @team = create :team, organization: @org
    @team.add_member(@user2)

    @org_repo = create :repository, owner: @org
    @org_issue = create :issue, repository: @org_repo, user: @org.admins.first
  end

  setup do
    ActionMailer::Base.deliveries.clear
    disable_feature_flag(:notifyd_issue_watch_activity_notify)
  end

  context "on issue creation" do
    test "originally mentioned user sees delivery" do
      issue = @mentioned_issue

      # this happens on create
      only = [Newsies::DeliverNotificationsJob, NotifySubscriptionStatusChangeJob]
      perform_enqueued_jobs(only: only) do
        issue.subscribe_mentioned
        issue.deliver_notifications
      end

      assert_delivered_web_notification(@user, issue, "mention")
      assert_delivered_email_notification(@user, issue, "mention")
    end

    test "originally mentioned user doesn't see deliveries if delivery via Notifyd is enabled" do
      enable_feature_flag(:notifyd_issue_watch_activity_notify, @user)
      issue = @mentioned_issue

      # this happens on create
      only = [Newsies::DeliverNotificationsJob, NotifySubscriptionStatusChangeJob]
      perform_enqueued_jobs(only: only) do
        issue.subscribe_mentioned
        issue.deliver_notifications
      end

      refute_delivered_web_notification(@user, issue)
      refute_delivered_email_notification(@user, issue)
    end unless GitHub.enterprise?

    test "originally mentioned user gets subscribed" do
      issue = @mentioned_issue

      # this happens on create
      only = [Newsies::DeliverNotificationsJob, NotifySubscriptionStatusChangeJob]
      perform_enqueued_jobs(only: only) do
        issue.subscribe_mentioned
        issue.deliver_notifications
      end

      status = GitHub.newsies.subscription_status(@user, @repo, issue).value
      assert status.valid?, status.inspect
      assert_match /mention/, status.reason
    end
  end

  context "when typo is fixed" do
    test "originally mentioned user gets unsubscribed" do
      issue = @mentioned_issue

      issue.body = "hi @user2"
      perform_enqueued_jobs(only: [UpdateSubscriptionsAndNotifyJob]) do
        issue.save!
      end

      status = GitHub.newsies.subscription_status(@user, @repo, issue).value
      assert !status.valid?, status.inspect
    end

    test "originally mentioned user with comment keeps subscription, while subscribing for new mention" do
      issue = @mentioned_issue
      comment = create :issue_comment, user: @user, issue: issue

      # They are already subscribed.
      status = GitHub.newsies.subscription_status(@user, @repo, issue).value
      assert status.valid?, status.inspect
      assert_match /mention/, status.reason

      # Change the body to no longer mention @user.
      issue.body = "hi @user2"
      perform_enqueued_jobs(only: [UpdateSubscriptionsAndNotifyJob]) do
        issue.save!
      end

      # They are still subscribed.
      status = GitHub.newsies.subscription_status(@user, @repo, issue).value
      assert status.valid?, status.inspect
      assert_match /mention/, status.reason

      # @user2 is now also mentioned.
      status = GitHub.newsies.subscription_status(@user2, @repo, issue).value
      assert status.valid?, status.inspect
      assert_match /mention/, status.reason
    end

    test "originally mentioned user with assignment keeps subscription, while subscribing new mention" do
      issue = @mentioned_issue

      # They're subscribed because of the mention.
      status = GitHub.newsies.subscription_status(@user, @repo, issue).value
      assert status.valid?, status.inspect
      assert_match /mention/, status.reason

      perform_enqueued_jobs(only: SubscribeAndNotifyJob) { issue.assignee = @user }

      # Now they're subscribed because of the assignment.
      status = GitHub.newsies.subscription_status(@user, @repo, issue).value
      assert status.valid?, status.inspect
      assert_match "assign", status.reason

      # Replace the issue body.
      issue.body = "hi @user2"
      perform_enqueued_jobs(only: [UpdateSubscriptionsAndNotifyJob]) do
        issue.save!
      end

      # They're still subscribed because of the assignment.
      status = GitHub.newsies.subscription_status(@user, @repo, issue).value
      assert status.valid?, status.inspect
      assert_match "assign", status.reason

      # @user2 is also subscribed.
      status = GitHub.newsies.subscription_status(@user2, @repo, issue).value
      assert status.valid?, status.inspect
      assert_match /mention/, status.reason
    end

    test "newly mentioned user gets subscribed" do
      issue = @mentioned_issue

      issue.body = "hi @user2"
      perform_enqueued_jobs(only: [UpdateSubscriptionsAndNotifyJob]) do
        issue.save!
      end

      status = GitHub.newsies.subscription_status(@user2, @repo, issue).value
      assert status.valid?, status.inspect
      assert_match /mention/, status.reason
    end

    test "only newly mentioned user gets notification" do
      issue = @mentioned_issue

      issue.body = "hi @user2 @owner"
      only = [Newsies::DeliverNotificationsJob, UpdateSubscriptionsAndNotifyJob]
      perform_enqueued_jobs(only: only) do
        issue.save!
      end

      assert_delivered_web_notification(@user2, issue, "mention")
      assert_delivered_email_notification(@user2, issue, "mention")
      refute_delivered_any_notifications(@owner)
    end

    test "newly mentioned user does not get notification if delivery via Notifyd is enabled" do
      enable_feature_flag(:notifyd_issue_watch_activity_notify, @user2)
      issue = @mentioned_issue

      issue.body = "hi @user2 @owner"
      only = [Newsies::DeliverNotificationsJob, UpdateSubscriptionsAndNotifyJob]
      perform_enqueued_jobs(only: only) do
        issue.save!
      end

      refute_delivered_web_notification(@user2, issue)
      refute_delivered_email_notification(@user2, issue)
      refute_delivered_any_notifications(@owner)
    end unless GitHub.enterprise?

    test "newly mentioned team gets email with correct reason" do
      issue = @org_issue

      issue.body = "ohai @#{@team.combined_slug}"
      only = [Newsies::DeliverNotificationsJob, UpdateSubscriptionsAndNotifyJob]
      perform_enqueued_jobs(only: only) { issue.save! }

      assert_delivered_web_notification(@user2, issue, "team-mentioned")
      assert_delivered_email_notification(@user2, issue, "team-mentioned")
    end
  end
end
