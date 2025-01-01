# typed: true
# frozen_string_literal: true

require "test_helper"

class SubscriptionsGistTest < GitHub::TestCase
  include DogstatsTestHelpers
  include GitHub::LoggerHelper

  fixtures do
    @org = create(:organization)
    @gist = create(:gist, owner: @org)
    @user = create(:user)
  end

  context "#notifyd_subscribe_to_thread" do
    test "subscribes to Gist thread for string reason manual in newsies and notifyd when notifyd feature flag is enabled" do
      GitHub.flipper[:notifyd_enable_gist_thread_subscriptions].enable

      GitHub.newsies.expects(:subscribe_to_thread).with(@user, @org, @gist, "manual", [])
      if GitHub.enterprise? # Notifyd is never enabled in enterprise
        Notifications::Subscriptions.expects(:notifyd_subscribe_to_thread).never
      else
        Notifications::Subscriptions.expects(:notifyd_subscribe_to_thread).with(@user, @org, @gist, "manual")
      end

      Notifications::Subscriptions.subscribe_to_thread(@user, @org, @gist, "manual")
    end

    test "subscribes to Gist thread for symbol reason manual in newsies and notifyd when notifyd feature flag is enabled" do
      GitHub.flipper[:notifyd_enable_gist_thread_subscriptions].enable

      GitHub.newsies.expects(:subscribe_to_thread).with(@user, @org, @gist, :manual, [])
      if GitHub.enterprise? # Notifyd is never enabled in enterprise
        Notifications::Subscriptions.expects(:notifyd_subscribe_to_thread).never
      else
        Notifications::Subscriptions.expects(:notifyd_subscribe_to_thread).with(@user, @org, @gist, "manual")
      end

      Notifications::Subscriptions.subscribe_to_thread(@user, @org, @gist, :manual)
    end

    test "subscribes to Gist thread for hash/symbol reason manual in newsies and notifyd when notifyd feature flag is enabled" do
      GitHub.flipper[:notifyd_enable_gist_thread_subscriptions].enable

      GitHub.newsies.expects(:subscribe_to_thread).with(@user, @org, @gist, { reason: :manual }, [])
      if GitHub.enterprise? # Notifyd is never enabled in enterprise
        Notifications::Subscriptions.expects(:notifyd_subscribe_to_thread).never
      else
        Notifications::Subscriptions.expects(:notifyd_subscribe_to_thread).with(@user, @org, @gist, "manual")
      end

      Notifications::Subscriptions.subscribe_to_thread(@user, @org, @gist, { reason: :manual })
    end

    test "subscribes to Gist thread for hash/string reason manual in newsies and notifyd when notifyd feature flag is enabled" do
      GitHub.flipper[:notifyd_enable_gist_thread_subscriptions].enable

      GitHub.newsies.expects(:subscribe_to_thread).with(@user, @org, @gist, { reason: "manual" }, [])
      if GitHub.enterprise? # Notifyd is never enabled in enterprise
        Notifications::Subscriptions.expects(:notifyd_subscribe_to_thread).never
      else
        Notifications::Subscriptions.expects(:notifyd_subscribe_to_thread).with(@user, @org, @gist, "manual")
      end

      Notifications::Subscriptions.subscribe_to_thread(@user, @org, @gist, { reason: "manual" })
    end

    test "subscribes to Gist thread only in newsies when notifyd feature flag is disabled" do
      GitHub.flipper[:notifyd_enable_gist_thread_subscriptions].disable
      GitHub.flipper[:notifyd_primary_gist].disable

      GitHub.newsies.expects(:subscribe_to_thread).with(@user, @org, @gist, "manual", [])
      Notifications::Subscriptions.expects(:notifyd_subscribe_to_thread).never

      Notifications::Subscriptions.subscribe_to_thread(@user, @org, @gist, "manual")
    end

    test "subscribes to Gist thread for reason author in newsies when notifyd feature flag is enabled" do
      GitHub.flipper[:notifyd_enable_gist_thread_subscriptions].enable

      GitHub.newsies.expects(:subscribe_to_thread).with(@user, @org, @gist, "author", [])
      Notifications::Subscriptions.expects(:notifyd_subscribe_to_thread).never

      Notifications::Subscriptions.subscribe_to_thread(@user, @org, @gist, "author")
    end

    context "notifyd is primary" do
      test "return notifyd results and log differences", skip_enterprise: true do
        GitHub.flipper[:notifyd_enable_gist_thread_subscriptions].enable(@user)
        GitHub.flipper[:notifyd_primary_gist].enable(@user)

        Notifications::Subscriptions.expects(:notifyd_subscribe_to_thread).with(@user, @org, @gist, "manual").returns(Notifyd::Responses::Boolean.new { true })
        GitHub.newsies.expects(:subscribe_to_thread).with(@user, @org, @gist, "manual", []).returns(Newsies::Responses::Boolean.new { false })

        response = Notifications::Subscriptions.subscribe_to_thread(@user, @org, @gist, "manual")
        assert response.value
        assert_equal response.class, Notifyd::Responses::Boolean

        assert_dogstats_increment(1, "notifications.subscriptions.differences", tags: ["method:subscribe_to_thread"])
      end

      test "suppresses all exceptions", skip_enterprise: true do
        GitHub.flipper[:notifyd_enable_gist_thread_subscriptions].enable(@user)
        GitHub.flipper[:notifyd_primary_gist].enable(@user)

        error = StandardError.new("boom!")
        Notifications::Subscriptions.expects(:notifyd_subscribe_to_thread).with(@user, @org, @gist, "manual").raises(error)
        GitHub.newsies.expects(:subscribe_to_thread).with(@user, @org, @gist, "manual", []).raises(error)

        assert_error_reported_with_message(StandardError, "boom!") do
          response = Notifications::Subscriptions.subscribe_to_thread(@user, @org, @gist, "manual")
          refute response.value
          assert_equal response.class, Notifyd::Responses::Boolean
        end
      end
    end

    context "newsies is primary" do
      test "return newsies results and log differences", skip_enterprise: true do
        GitHub.flipper[:notifyd_enable_gist_thread_subscriptions].enable
        GitHub.flipper[:notifyd_primary_gist].disable

        Notifications::Subscriptions.expects(:notifyd_subscribe_to_thread).with(@user, @org, @gist, "manual").returns(Notifyd::Responses::Boolean.new { false })
        GitHub.newsies.expects(:subscribe_to_thread).with(@user, @org, @gist, "manual", []).returns(Newsies::Responses::Boolean.new { true })

        expected_log = {
          "Body" => "found differences in results between notifyd and newsies",
          "code.namespace" => "Notifications::Subscriptions",
          "code.function" => "subscribe_to_thread",
          "gh.notifications.response" => true,
          "gh.notifyd.response" => false
        }
        assert_logged(**expected_log) do
          response = Notifications::Subscriptions.subscribe_to_thread(@user, @org, @gist, "manual")
          assert response.value
          assert_equal response.class, Newsies::Responses::Boolean

          assert_dogstats_increment(1, "notifications.subscriptions.differences", tags: ["method:subscribe_to_thread"])
        end
      end

      test "does not suppress newsies errors", skip_enterprise: true do
        GitHub.flipper[:notifyd_enable_gist_thread_subscriptions].enable
        GitHub.flipper[:notifyd_primary_gist].disable

        error = StandardError.new("boom!")
        GitHub.newsies.expects(:subscribe_to_thread).with(@user, @org, @gist, "manual", []).raises(error)
        Notifications::Subscriptions.expects(:notifyd_subscribe_to_thread).with(@user, @org, @gist, "manual").never

        NotificationsFailbot.expects(:report).with(error, equals({
          system: "newsies", fn: "subscribe_to_thread", catalog_service: "github/notifications"
        }))
        NotificationsFailbot.expects(:report).with(error, {
          system: "notifyd", fn: "subscribe_to_thread", catalog_service: "github/notifications"
        }).never

        assert_raises StandardError do
          Notifications::Subscriptions.subscribe_to_thread(@user, @org, @gist, "manual")
        end
      end

      test "suppresses notifyd errors", skip_enterprise: true do
        GitHub.flipper[:notifyd_enable_gist_thread_subscriptions].enable
        GitHub.flipper[:notifyd_primary_gist].disable

        GitHub.newsies.expects(:subscribe_to_thread).with(@user, @org, @gist, "manual", []).returns(Newsies::Responses::Boolean.new { true })
        Notifications::Subscriptions.expects(:notifyd_subscribe_to_thread).with(@user, @org, @gist, "manual").raises(StandardError.new("boom!"))

        expected_log = {
          "Body" => "found differences in results between notifyd and newsies",
          "code.namespace" => "Notifications::Subscriptions",
          "code.function" => "subscribe_to_thread",
          "gh.notifications.response" => true,
          "gh.notifyd.response" => false
        }
        assert_logged(**expected_log) do
          assert_error_reported_with_message(StandardError, "boom!") do
            response = Notifications::Subscriptions.subscribe_to_thread(@user, @org, @gist, "manual")
            assert response.value
            assert_equal response.class, Newsies::Responses::Boolean

            assert_dogstats_increment(1, "notifications.subscriptions.differences", tags: ["method:subscribe_to_thread"])
          end
        end
      end
    end
  end

  context "#unsubscribe_from_thread" do
    test "unsubscribes from Gist thread in newsies and notifyd when notifyd feature flag is enabled" do
      GitHub.flipper[:notifyd_enable_gist_thread_subscriptions].enable

      GitHub.newsies.expects(:unsubscribe_from_thread).with(@user, @gist)
      if GitHub.enterprise? # Notifyd is never enabled in enterprise
        Notifications::Subscriptions.expects(:notifyd_unsubscribe_from_thread).never
      else
        Notifications::Subscriptions.expects(:notifyd_unsubscribe_from_thread).with(@user, @gist)
      end

      Notifications::Subscriptions.unsubscribe_from_thread(@user, @gist)
    end

    test "unsubscribes from Gist thread in newsies when notifyd feature flag is disabled" do
      GitHub.flipper[:notifyd_enable_gist_thread_subscriptions].disable
      GitHub.flipper[:notifyd_primary_gist].disable

      GitHub.newsies.expects(:unsubscribe_from_thread).with(@user, @gist)
      Notifications::Subscriptions.expects(:notifyd_unsubscribe_from_thread).never

      Notifications::Subscriptions.unsubscribe_from_thread(@user,  @gist)
    end

    context "notifyd is primary" do
      test "return notifyd results and log differences", skip_enterprise: true do
        GitHub.flipper[:notifyd_enable_gist_thread_subscriptions].enable(@user)
        GitHub.flipper[:notifyd_primary_gist].enable(@user)

        Notifications::Subscriptions.expects(:notifyd_unsubscribe_from_thread).with(@user, @gist).returns(Notifyd::Responses::Boolean.new { false })
        GitHub.newsies.expects(:unsubscribe_from_thread).with(@user, @gist).returns(Newsies::Response.new { nil })

        expected_log = {
          "Body" => "found differences in results between notifyd and newsies",
          "code.namespace" => "Notifications::Subscriptions",
          "code.function" => "unsubscribe_from_thread",
          "gh.notifications.response" => "",
          "gh.notifyd.response" => false
        }
        assert_logged(**expected_log) do
          response = Notifications::Subscriptions.unsubscribe_from_thread(@user, @gist)
          refute response.value
          assert_equal response.class, Notifyd::Responses::Boolean

          assert_dogstats_increment(1, "notifications.subscriptions.differences", tags: ["method:unsubscribe_from_thread"])
        end
      end

      test "catches all exceptions", skip_enterprise: true do
        GitHub.flipper[:notifyd_enable_gist_thread_subscriptions].enable(@user)
        GitHub.flipper[:notifyd_primary_gist].enable(@user)

        error = StandardError.new("boom!")
        Notifications::Subscriptions.expects(:notifyd_unsubscribe_from_thread).with(@user, @gist).raises(error)
        GitHub.newsies.expects(:unsubscribe_from_thread).with(@user, @gist).raises(error)

        assert_error_reported_with_message(StandardError, "boom!") do
          response = Notifications::Subscriptions.unsubscribe_from_thread(@user, @gist)
          refute response.value
          assert_equal response.class, Notifyd::Responses::Boolean
        end
      end
    end

    context "newsies is primary" do
      test "return newsies results and log differences", skip_enterprise: true do
        GitHub.flipper[:notifyd_enable_gist_thread_subscriptions].enable
        GitHub.flipper[:notifyd_primary_gist].disable

        Notifications::Subscriptions.expects(:notifyd_unsubscribe_from_thread).with(@user, @gist).returns(Notifyd::Responses::Boolean.new { false })
        GitHub.newsies.expects(:unsubscribe_from_thread).with(@user, @gist).returns(Newsies::Response.new { true })

        expected_log = {
          "Body" => "found differences in results between notifyd and newsies",
          "code.namespace" => "Notifications::Subscriptions",
          "code.function" => "unsubscribe_from_thread",
          "gh.notifications.response" => true,
          "gh.notifyd.response" => false
        }
        assert_logged(**expected_log) do
          response = Notifications::Subscriptions.unsubscribe_from_thread(@user, @gist)
          assert response.value
          assert_equal response.class, Newsies::Response

          assert_dogstats_increment(1, "notifications.subscriptions.differences", tags: ["method:unsubscribe_from_thread"])
        end
      end

      test "does not suppress newsies errors", skip_enterprise: true do
        GitHub.flipper[:notifyd_enable_gist_thread_subscriptions].enable
        GitHub.flipper[:notifyd_primary_gist].disable

        error = StandardError.new("boom!")
        GitHub.newsies.expects(:unsubscribe_from_thread).with(@user, @gist).raises(error)
        Notifications::Subscriptions.expects(:notifyd_unsubscribe_from_thread).with(@user, @gist).never

        NotificationsFailbot.expects(:report).with(error, {
          system: "notifyd", fn: "unsubscribe_from_thread", catalog_service: "github/notifications"
        }).never
        NotificationsFailbot.expects(:report).with(error, equals({
          system: "newsies", fn: "unsubscribe_from_thread", catalog_service: "github/notifications"
        }))

        assert_raises StandardError do
          Notifications::Subscriptions.unsubscribe_from_thread(@user, @gist)
        end
      end

      test "suppresses notifyd errors", skip_enterprise: true do
        GitHub.flipper[:notifyd_enable_gist_thread_subscriptions].enable
        GitHub.flipper[:notifyd_primary_gist].disable

        GitHub.newsies.expects(:unsubscribe_from_thread).with(@user, @gist).returns(Newsies::Responses::Boolean.new { true })
        Notifications::Subscriptions.expects(:notifyd_unsubscribe_from_thread).with(@user, @gist).raises(StandardError.new("boom!"))

        expected_log = {
          "Body" => "found differences in results between notifyd and newsies",
          "code.namespace" => "Notifications::Subscriptions",
          "code.function" => "unsubscribe_from_thread",
          "gh.notifications.response" => true,
          "gh.notifyd.response" => false
        }
        assert_logged(**expected_log) do
          assert_error_reported_with_message(StandardError, "boom!") do
            response = Notifications::Subscriptions.unsubscribe_from_thread(@user, @gist)
            assert response.value
            assert_equal response.class, Newsies::Responses::Boolean

            assert_dogstats_increment(1, "notifications.subscriptions.differences", tags: ["method:unsubscribe_from_thread"])
          end
        end
      end
    end
  end

  context "#subscription_status" do
    test "returns subscription status from Notifyd if Notifyd a primary storage" do
      GitHub.flipper[:notifyd_enable_gist_thread_subscriptions].enable(@user)
      GitHub.flipper[:notifyd_primary_gist].enable(@user)

      if GitHub.enterprise? # Notifyd is never enabled in enterprise
        Notifications::Subscriptions.expects(:notifyd_subscription_status).never
        GitHub.newsies.expects(:subscription_status).with(@user, @gist.owner, @gist)
      else
        Notifications::Subscriptions.expects(:notifyd_subscription_status).with(@user, @gist.owner, @gist)
      end

      Notifications::Subscriptions.subscription_status(@user, @gist.owner, @gist)
    end

    test "returns subscription status from Newsies if Notifyd is not a primary storage" do
      GitHub.flipper[:notifyd_primary_gist].disable

      Notifications::Subscriptions.expects(:notifyd_subscription_status).never
      GitHub.newsies.expects(:subscription_status).with(@user, @gist.owner, @gist)

      Notifications::Subscriptions.subscription_status(@user, @gist.owner, @gist)
    end
  end
end
