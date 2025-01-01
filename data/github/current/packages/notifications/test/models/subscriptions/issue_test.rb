# typed: true
# frozen_string_literal: true

require "test_helper"

class SubscriptionsIssueTest < GitHub::TestCase
  include DogstatsTestHelpers
  include GitHub::LoggerHelper

  fixtures do
    @issue = create(:issue)
    @repository = @issue.repository
    @user = @repository.owner

    @issue2 = create(:issue)
    @repo2 = @issue2.repository
  end

  context "#notifyd_subscribe_to_thread" do
    test "subscribes to Issue thread for string reason manual only in newsies", enterprise_only: true, feature_enabled: :notifyd_enable_issue_thread_subscriptions do
      GitHub.newsies.expects(:subscribe_to_thread).with(@user, @repository, @issue, "manual", [])
      Notifications::Subscriptions.expects(:notifyd_subscribe_to_thread).never

      Notifications::Subscriptions.subscribe_to_thread(@user, @repository, @issue, "manual")
    end

    test "subscribes to Issue thread for string reason manual in newsies and notifyd", skip_enterprise: true, feature_enabled: :notifyd_enable_issue_thread_subscriptions do
      GitHub.newsies.expects(:subscribe_to_thread).with(@user, @repository, @issue, "manual", [])
      Notifications::Subscriptions.expects(:notifyd_subscribe_to_thread).with(@user, @repository, @issue, "manual")

      Notifications::Subscriptions.subscribe_to_thread(@user, @repository, @issue, "manual")
    end

    test "subscribes to Issue thread for string reason manual only in newsies if is from a pull request", skip_enterprise: true, feature_enabled: :notifyd_enable_issue_thread_subscriptions do
      issue = create(:pull_request, :disable_disk_access).issue
      repository = issue.repository
      user = repository.owner

      GitHub.newsies.expects(:subscribe_to_thread).with(user, repository, issue, "manual", [])
      Notifications::Subscriptions.expects(:notifyd_subscribe_to_thread).never

      Notifications::Subscriptions.subscribe_to_thread(user, repository, issue, "manual")
    end

    test "subscribes to Issue thread for hash/symbol reason manual only in newsies", enterprise_only: true, feature_enabled: :notifyd_enable_issue_thread_subscriptions do
      GitHub.newsies.expects(:subscribe_to_thread).with(@user, @repository, @issue, { reason: :manual }, [])
      Notifications::Subscriptions.expects(:notifyd_subscribe_to_thread).never

      Notifications::Subscriptions.subscribe_to_thread(@user, @repository, @issue, { reason: :manual })
    end

    test "subscribes to Issue thread for hash/symbol reason manual in newsies and notifyd", skip_enterprise: true, feature_enabled: :notifyd_enable_issue_thread_subscriptions do
      GitHub.newsies.expects(:subscribe_to_thread).with(@user, @repository, @issue, { reason: :manual }, [])
      Notifications::Subscriptions.expects(:notifyd_subscribe_to_thread).with(@user, @repository, @issue, "manual")

      Notifications::Subscriptions.subscribe_to_thread(@user, @repository, @issue, { reason: :manual })
    end

    test "subscribes to Issue thread only in newsies", skip_enterprise: true, feature_disabled: :notifyd_enable_issue_thread_subscriptions do
      GitHub.newsies.expects(:subscribe_to_thread).with(@user, @repository, @issue, "manual", [])
      Notifications::Subscriptions.expects(:notifyd_subscribe_to_thread).never

      Notifications::Subscriptions.subscribe_to_thread(@user, @repository, @issue, "manual")
    end

    context "notifyd is primary", skip_enterprise: true do
      test "return notifyd results and log differences" do
        GitHub.flipper[:notifyd_enable_issue_thread_subscriptions].enable
        GitHub.flipper[:notifyd_issue_watch_activity_notify].enable

        Notifications::Subscriptions.expects(:notifyd_subscribe_to_thread).with(@user, @repository, @issue, "manual").returns(Notifyd::Responses::Boolean.new { true })
        GitHub.newsies.expects(:subscribe_to_thread).with(@user, @repository, @issue, "manual", []).returns(Newsies::Responses::Boolean.new { false })

        response = Notifications::Subscriptions.subscribe_to_thread(@user, @repository, @issue, "manual")
        assert response.value
        assert_equal response.class, Notifyd::Responses::Boolean

        assert_dogstats_increment(1, "notifications.subscriptions.differences", tags: ["method:subscribe_to_thread"])
      end

      test "suppresses all exceptions" do
        GitHub.flipper[:notifyd_enable_issue_thread_subscriptions].enable
        GitHub.flipper[:notifyd_issue_watch_activity_notify].enable

        error = StandardError.new("boom!")
        Notifications::Subscriptions.expects(:notifyd_subscribe_to_thread).with(@user, @repository, @issue, "manual").raises(error)
        GitHub.newsies.expects(:subscribe_to_thread).with(@user, @repository, @issue, "manual", []).raises(error)

        assert_error_reported_with_message(StandardError, "boom!") do
          response = Notifications::Subscriptions.subscribe_to_thread(@user, @repository, @issue, "manual")
          refute response.value
          assert_equal response.class, Notifyd::Responses::Boolean
        end
      end
    end

    context "newsies is primary", skip_enterprise: true, feature_enabled: :notifyd_enable_issue_thread_subscriptions, feature_disabled: :notifyd_issue_watch_activity_notify do
      test "return newsies results and log differences" do
        Notifications::Subscriptions.expects(:notifyd_subscribe_to_thread).with(@user, @repository, @issue, "manual").returns(Notifyd::Responses::Boolean.new { false })
        GitHub.newsies.expects(:subscribe_to_thread).with(@user, @repository, @issue, "manual", []).returns(Newsies::Responses::Boolean.new { true })

        expected_log = {
          "Body" => "found differences in results between notifyd and newsies",
          "code.namespace" => "Notifications::Subscriptions",
          "code.function" => "subscribe_to_thread",
          "gh.notifications.response" => true,
          "gh.notifyd.response" => false
        }
        assert_logged(**expected_log) do
          response = Notifications::Subscriptions.subscribe_to_thread(@user, @repository, @issue, "manual")
          assert response.value
          assert_equal response.class, Newsies::Responses::Boolean

          assert_dogstats_increment(1, "notifications.subscriptions.differences", tags: ["method:subscribe_to_thread"])
        end
      end

      test "does not suppress newsies errors" do
        error = StandardError.new("boom!")
        GitHub.newsies.expects(:subscribe_to_thread).with(@user, @repository, @issue, "manual", []).raises(error)
        Notifications::Subscriptions.expects(:notifyd_subscribe_to_thread).with(@user, @repository, @issue, "manual").never

        NotificationsFailbot.expects(:report).with(error, {
          system: "notifyd", fn: "subscribe_to_thread", catalog_service: "github/notifications"
        }).never
        NotificationsFailbot.expects(:report).with(error, {
          system: "newsies", fn: "subscribe_to_thread", catalog_service: "github/notifications"
        })

        assert_raises StandardError do
          Notifications::Subscriptions.subscribe_to_thread(@user, @repository, @issue, "manual")
        end
      end

      test "suppresses notifyd errors" do
        GitHub.newsies.expects(:subscribe_to_thread).with(@user, @repository, @issue, "manual", []).returns(Newsies::Responses::Boolean.new { true })
        Notifications::Subscriptions.expects(:notifyd_subscribe_to_thread).with(@user, @repository, @issue, "manual").raises(StandardError.new("boom!"))

        expected_log = {
          "Body" => "found differences in results between notifyd and newsies",
          "code.namespace" => "Notifications::Subscriptions",
          "code.function" => "subscribe_to_thread",
          "gh.notifications.response" => true,
          "gh.notifyd.response" => false
        }
        assert_logged(**expected_log) do
          assert_error_reported_with_message(StandardError, "boom!") do
            response = Notifications::Subscriptions.subscribe_to_thread(@user, @repository, @issue, "manual")
            assert response.value
            assert_equal response.class, Newsies::Responses::Boolean

            assert_dogstats_increment(1, "notifications.subscriptions.differences", tags: ["method:subscribe_to_thread"])
          end
        end
      end
    end
  end

  context "#unsubscribe_from_thread" do
    test "unsubscribes from Issue thread only in newsies", enterprise_only: true, feature_enabled: :notifyd_enable_issue_thread_subscriptions do
      GitHub.newsies.expects(:unsubscribe_from_thread).with(@user, @issue)
      Notifications::Subscriptions.expects(:notifyd_unsubscribe_from_thread).never

      Notifications::Subscriptions.unsubscribe_from_thread(@user, @issue)
    end

    test "subscribes from Issue thread in newsies and notifyd", skip_enterprise: true, feature_enabled: :notifyd_enable_issue_thread_subscriptions do
      GitHub.newsies.expects(:unsubscribe_from_thread).with(@user, @issue)
      Notifications::Subscriptions.expects(:notifyd_unsubscribe_from_thread).with(@user, @issue)

      Notifications::Subscriptions.unsubscribe_from_thread(@user, @issue)
    end

    test "unsubscribes from Issue thread only in newsies if is from a pull request", skip_enterprise: true, feature_enabled: :notifyd_enable_issue_thread_subscriptions do
      issue = create(:pull_request, :disable_disk_access).issue
      repository = issue.repository
      user = repository.owner

      GitHub.newsies.expects(:unsubscribe_from_thread).with(user, issue)
      Notifications::Subscriptions.expects(:notifyd_unsubscribe_from_thread).never

      Notifications::Subscriptions.unsubscribe_from_thread(user, issue)
    end

    test "unsubscribes from Issue thread only in newsies", skip_enterprise: true, feature_disabled: :notifyd_enable_issue_thread_subscriptions do
      GitHub.newsies.expects(:unsubscribe_from_thread).with(@user, @issue)
      Notifications::Subscriptions.expects(:notifyd_unsubscribe_from_thread).never

      Notifications::Subscriptions.unsubscribe_from_thread(@user, @issue)
    end

    context "delete multiple subscriptions for user", skip_enterprise: true do
      test "deletes multiple subscriptions on newsies in FF disabled", feature_disabled: :notifyd_delete_thread_subscriptions do
        GitHub.newsies.subscribe_to_thread(@user, @repository, @issue, "manual")
        GitHub.newsies.subscribe_to_thread(@user, @repo2, @issue2, "manual")

        response = GitHub.newsies.subscribed_threads(@user, [@repository, @repo2], "Issue")
        assert_same_elements [@issue.id, @issue2.id], response.map(&:thread_id).map(&:to_i)
        subscription_ids = Newsies::ThreadSubscription.for_user(@user.id).pluck(:id)

        Notifications::Subscriptions.expects(:notifyd_delete_thread_subscription).never
        Notifications::Subscriptions.expects(:notifyd_delete_thread_subscription).never

        perform_enqueued_jobs(only: Notifyd::SyncDeleteThreadSubscriptionsJob) do
          Notifications::Subscriptions.delete_thread_subscriptions(
            user_id: @user.id,
            thread_subscription_ids: subscription_ids
          )
        end

        response = GitHub.newsies.subscribed_threads(@user, [@repository, @repo2], "Issue")
        assert_empty response
      end

      test "deletes multiple subscriptions on notifyd and newsies in FF enabled", feature_enabled: :notifyd_delete_thread_subscriptions do
        GitHub.newsies.subscribe_to_thread(@user, @repository, @issue, "manual")
        GitHub.newsies.subscribe_to_thread(@user, @repo2, @issue2, "manual")

        response = GitHub.newsies.subscribed_threads(@user, [@repository, @repo2], "Issue")
        assert_same_elements [@issue.id, @issue2.id], response.map(&:thread_id).map(&:to_i)
        subscription_ids = Newsies::ThreadSubscription.for_user(@user.id).pluck(:id)

        Notifications::Subscriptions.expects(:notifyd_delete_thread_subscription).with(@user, @issue).once.returns(Notifyd::Responses::Boolean.new { true })
        Notifications::Subscriptions.expects(:notifyd_delete_thread_subscription).with(@user, @issue2).once.returns(Notifyd::Responses::Boolean.new { true })

        perform_enqueued_jobs(only: Notifyd::SyncDeleteThreadSubscriptionsJob) do
          Notifications::Subscriptions.delete_thread_subscriptions(
            user_id: @user.id,
            thread_subscription_ids: subscription_ids
          )
        end

        response = GitHub.newsies.subscribed_threads(@user, [@repository, @repo2], "Issue")
        assert_empty response
      end

      test "catches exception if notifyd throws an error", feature_enabled: :notifyd_delete_thread_subscriptions do
        GitHub.newsies.subscribe_to_thread(@user, @repository, @issue, "manual")
        GitHub.newsies.subscribe_to_thread(@user, @repo2, @issue2, "manual")

        response = GitHub.newsies.subscribed_threads(@user, [@repository, @repo2], "Issue")
        assert_same_elements [@issue.id, @issue2.id], response.map(&:thread_id).map(&:to_i)
        subscription_ids = Newsies::ThreadSubscription.for_user(@user.id).pluck(:id)

        Notifications::Subscriptions.expects(:notifyd_schedule_delete_thread_subscriptions).throws(StandardError.new)

        result = Notifications::Subscriptions.delete_thread_subscriptions(
          user_id: @user.id,
          thread_subscription_ids: subscription_ids
        )

        refute result.value
      end
    end

    context "notifyd is primary", skip_enterprise: true do
      test "return notifyd results and log differences" do
        GitHub.flipper[:notifyd_enable_issue_thread_subscriptions].enable
        GitHub.flipper[:notifyd_issue_watch_activity_notify].enable

        Notifications::Subscriptions.expects(:notifyd_unsubscribe_from_thread).with(@user, @issue).returns(Notifyd::Responses::Boolean.new { false })
        GitHub.newsies.expects(:unsubscribe_from_thread).with(@user, @issue).returns(Newsies::Response.new { nil })

        expected_log = {
          "Body" => "found differences in results between notifyd and newsies",
          "code.namespace" => "Notifications::Subscriptions",
          "code.function" => "unsubscribe_from_thread",
          "gh.notifications.response" => "",
          "gh.notifyd.response" => false
        }
        assert_logged(**expected_log) do
          response = Notifications::Subscriptions.unsubscribe_from_thread(@user, @issue)
          refute response.value
          assert_equal response.class, Notifyd::Responses::Boolean

          assert_dogstats_increment(1, "notifications.subscriptions.differences", tags: ["method:unsubscribe_from_thread"])
        end
      end

      test "catches all exceptions" do
        GitHub.flipper[:notifyd_enable_issue_thread_subscriptions].enable
        GitHub.flipper[:notifyd_issue_watch_activity_notify].enable

        error = StandardError.new("boom!")
        Notifications::Subscriptions.expects(:notifyd_unsubscribe_from_thread).with(@user, @issue).raises(error)
        GitHub.newsies.expects(:unsubscribe_from_thread).with(@user, @issue).raises(error)

        assert_error_reported_with_message(StandardError, "boom!") do
          response = Notifications::Subscriptions.unsubscribe_from_thread(@user, @issue)
          refute response.value
          assert_equal response.class, Notifyd::Responses::Boolean
        end
      end
    end

    context "newsies is primary", skip_enterprise: true, feature_enabled: :notifyd_enable_issue_thread_subscriptions, feature_disabled: :notifyd_issue_watch_activity_notify do
      test "return newsies results and log differences" do
        Notifications::Subscriptions.expects(:notifyd_unsubscribe_from_thread).with(@user, @issue).returns(Notifyd::Responses::Boolean.new { false })
        GitHub.newsies.expects(:unsubscribe_from_thread).with(@user, @issue).returns(Newsies::Responses::Boolean.new { true })

        expected_log = {
          "Body" => "found differences in results between notifyd and newsies",
          "code.namespace" => "Notifications::Subscriptions",
          "code.function" => "unsubscribe_from_thread",
          "gh.notifications.response" => true,
          "gh.notifyd.response" => false
        }
        assert_logged(**expected_log) do
          response = Notifications::Subscriptions.unsubscribe_from_thread(@user, @issue)
          assert response.value
          assert_equal response.class, Newsies::Responses::Boolean

          assert_dogstats_increment(1, "notifications.subscriptions.differences", tags: ["method:unsubscribe_from_thread"])
        end
      end

      test "does not suppress newsies errors" do
        error = StandardError.new("boom!")
        GitHub.newsies.expects(:unsubscribe_from_thread).with(@user, @issue).raises(error)
        Notifications::Subscriptions.expects(:notifyd_unsubscribe_from_thread).with(@user, @issue).never

        NotificationsFailbot.expects(:report).with(error, {
          system: "notifyd", fn: "unsubscribe_from_thread", catalog_service: "github/notifications"
        }).never
        NotificationsFailbot.expects(:report).with(error, {
          system: "newsies", fn: "unsubscribe_from_thread", catalog_service: "github/notifications"
        })

        assert_raises StandardError do
          Notifications::Subscriptions.unsubscribe_from_thread(@user, @issue)
        end
      end

      test "suppresses notifyd errors" do
        GitHub.newsies.expects(:unsubscribe_from_thread).with(@user, @issue).returns(Newsies::Responses::Boolean.new { true })
        Notifications::Subscriptions.expects(:notifyd_unsubscribe_from_thread).with(@user, @issue).raises(StandardError.new("boom!"))

        expected_log = {
          "Body" => "found differences in results between notifyd and newsies",
          "code.namespace" => "Notifications::Subscriptions",
          "code.function" => "unsubscribe_from_thread",
          "gh.notifications.response" => true,
          "gh.notifyd.response" => false
        }
        assert_logged(**expected_log) do
          assert_error_reported_with_message(StandardError, "boom!") do
            response = Notifications::Subscriptions.unsubscribe_from_thread(@user, @issue)
            assert response.value
            assert_equal response.class, Newsies::Responses::Boolean

            assert_dogstats_increment(1, "notifications.subscriptions.differences", tags: ["method:unsubscribe_from_thread"])
          end
        end
      end
    end
  end
end
