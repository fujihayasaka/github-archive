# typed: true
# frozen_string_literal: true

require "test_helper"

class StafftoolsUserNotificationDeliveriesTest < GitHub::TestCase
  include NewsiesHelper

  fixtures do
    @repo_owner, @issue_author, @discussion_author, @mentionee, @notifyd_mentionee = create_list(:verified_user, 5)

    enable_notifications_for_user(@repo_owner, enabled_handlers: ["email"])
    enable_notifications_for_user(@issue_author, enabled_handlers: %w[email web])
    enable_notifications_for_user(@discussion_author, enabled_handlers: %w[email web])
    enable_notifications_for_user(@mentionee, enabled_handlers: ["web"], direct_mention_mobile_push: true)
    enable_notifications_for_user(@notifyd_mentionee, enabled_handlers: %w[web email], direct_mention_mobile_push: true)

    GitHub.flipper[:publish_events_to_notifyd].disable
    GitHub.flipper[:notifyd_issue_watch_activity_notify].disable
    GitHub.flipper[:notifyd_issue_watch_activity_notify].enable(@notifyd_mentionee)
    GitHub.flipper[:notifyd_enable_issues_explicit_auto_subscriptions].disable
    GitHub.flipper[:notifyd_enable_issues_explicit_auto_subscriptions].enable(@issue_author)

    @repo = create(:repository, owner: @repo_owner, has_discussions: true)
    @repo_owner.watch_repo(@repo)

    only = [Newsies::DeliverNotificationsJob, SubscribeAndNotifyJob]
    @issue = perform_enqueued_jobs(only: only) do
      create(:issue, repository: @repo, user: @issue_author, body: "/cc @#{@mentionee} @#{@notifyd_mentionee}")
    end

    only = [Newsies::DeliverNotificationsJob, SubscribeAndNotifyJob]
    @comment = perform_enqueued_jobs(only: only) do
      user = create(:user)
      GitHub.flipper[:notifyd_enable_issues_explicit_auto_subscriptions].enable(user)
      create(:issue_comment, :wait_for_orchestration, issue: @issue, user: user, body: "Also @#{@mentionee} @#{@notifyd_mentionee}...")
    end

    only = [Newsies::DeliverNotificationsJob, SubscribeAndNotifyJob]
    @discussion = perform_enqueued_jobs(only: only) do
      create(:discussion, repository: @repo, user: @discussion_author, title: "title", body: "/cc @#{@mentionee}")
    end

    only = [Newsies::DeliverNotificationsJob, SubscribeAndNotifyJob]
    @discussion_comment = perform_enqueued_jobs(only: only) do
      create(:discussion_comment, discussion: @discussion, body: "Also @#{@mentionee}...")
    end
  end

  setup do
    @email_delivery = stub(handler: "email", delivered_at: @issue.updated_at)
    @web_delivery = stub(handler: "web", delivered_at: @issue.updated_at)
    @mobile_push_delivery = stub(handler: "mobile-push", delivered_at: @issue.updated_at)
  end

  context ".for_thread" do
    test "retrieves users who were notified for an issue" do
      deliveries_by_user_id = Stafftools::UserNotificationDeliveries
        .for_thread(@issue)
        .index_by { |d| d.user.id }

      if GitHub.enterprise?
        assert_equal 3, deliveries_by_user_id.length
        assert_equal "web", deliveries_by_user_id[@notifyd_mentionee.id].handlers
      else
        assert_equal 2, deliveries_by_user_id.length
        refute deliveries_by_user_id[@notifyd_mentionee.id]
      end
      assert_equal "email", deliveries_by_user_id[@repo_owner.id].handlers
      assert_equal "web", deliveries_by_user_id[@mentionee.id].handlers
    end

    test "retrieves users who were notified for an issue comment" do
      deliveries_by_user_id = Stafftools::UserNotificationDeliveries
        .for_thread(@comment)
        .index_by { |d| d.user.id }

      if GitHub.enterprise?
        assert_equal 4, deliveries_by_user_id.length, deliveries_by_user_id.values.inspect
        assert_equal "web", deliveries_by_user_id[@notifyd_mentionee.id].handlers
      else
        assert_equal 3, deliveries_by_user_id.length, deliveries_by_user_id.values.inspect
        refute deliveries_by_user_id[@notifyd_mentionee.id]
      end
      assert_equal "email", deliveries_by_user_id[@repo_owner.id].handlers
      assert_equal "web", deliveries_by_user_id[@mentionee.id].handlers
      assert_equal "email, web", deliveries_by_user_id[@issue_author.id].handlers
    end

    test "retrieves users who were notified for a discussion" do
      deliveries_by_user_id = Stafftools::UserNotificationDeliveries
        .for_thread(@discussion)
        .index_by { |d| d.user.id }

      assert_equal 2, deliveries_by_user_id.length
      assert_equal "email", deliveries_by_user_id[@repo_owner.id].handlers
      assert_equal "web", deliveries_by_user_id[@mentionee.id].handlers
    end

    test "retrieves users who were notified for a discussion that was converted from an issue" do
      only = [Newsies::DeliverNotificationsJob, SubscribeAndNotifyJob]
      discussion = perform_enqueued_jobs(only: only) do
        create(:discussion, repository: @repo, user: @discussion_author, title: "title", body: "/cc @#{@mentionee}", issue: @issue)
      end

      deliveries_by_user_id = Stafftools::UserNotificationDeliveries
        .for_thread(discussion)
        .index_by { |d| d.user.id }

      assert_equal 2, deliveries_by_user_id.length
      assert_equal "email", deliveries_by_user_id[@repo_owner.id].handlers
      assert_equal "web", deliveries_by_user_id[@mentionee.id].handlers
    end

    test "retrieves users who were notified for a discussion comment" do
      deliveries_by_user_id = Stafftools::UserNotificationDeliveries
        .for_thread(@discussion_comment)
        .index_by { |d| d.user.id }

      assert_equal 3, deliveries_by_user_id.length, deliveries_by_user_id.values.inspect
      assert_equal "email", deliveries_by_user_id[@repo_owner.id].handlers
      assert_equal "web", deliveries_by_user_id[@mentionee.id].handlers
      assert_equal "email, web", deliveries_by_user_id[@discussion_author.id].handlers
    end
  end

  context "#handlers" do
    test "extracts singular handlers" do
      delivery = Stafftools::UserNotificationDeliveries.new(@repo_owner, [@web_delivery])
      assert_equal "web", delivery.handlers
    end

    test "extracts and sorts multiple handlers" do
      delivery = Stafftools::UserNotificationDeliveries.new(
        @repo_owner,
        [@web_delivery, @mobile_push_delivery, @email_delivery],
      )
      assert_equal "email, mobile-push, web", delivery.handlers
    end

    test "removes duplicates" do
      delivery = Stafftools::UserNotificationDeliveries.new(
        @repo_owner,
        [@email_delivery, @email_delivery],
      )
      assert_equal "email", delivery.handlers
    end
  end
end
