# typed: true
# frozen_string_literal: true

require "test_helper"

class NewsFeedAnalyticsTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @repo = create(:repository, owner: @user)
  end

  setup do
    attrs = Stratocaster::Attributes::Watch.new
    attrs.from(@repo.id, @user.id, "started")
    @event = Stratocaster::Event.new(attrs.to_hash)

    @event_group = {
      quantity: 1,
      includes_viewer: false,
      type: "WatchEvent",
    }
  end

  context "#event_click_attributes" do
    test "returns with event" do
      target = "repo"
      attributes = NewsFeedAnalytics.event_click_attributes(@event, event_details: {}, target: target,
                                                            viewer_id: nil)

      expected_namespace = "news_feed.event.click"
      expected_payload = attributes["payload"] = {
        action_target: "repo",
        user_id: nil,
        org_id: nil,
        originating_url: nil,
        event_group: nil,
        target_type: NewsFeedAnalytics::TARGET_TYPE_EVENT,
        event: {
          repo_id: @repo.id,
          actor_id: @user.id,
          public: true,
          type: "WatchEvent",
          target_id: nil,
          id: nil,
        },
        feed_card: {
          card_retrieved_id: @event.retrieved_id,
        }
      }

      refute_nil attributes["hydro-click"]
      refute_nil attributes["hydro-click-hmac"]

      attrs_json = JSON.parse(attributes["hydro-click"]).deep_symbolize_keys
      assert_equal expected_namespace, attrs_json[:event_type]
      assert_equal expected_payload, attrs_json[:payload]
    end
  end

  context "#event_group_click_attribute" do
    test "returns with event group" do
      attributes = NewsFeedAnalytics.event_group_click_attributes(@event_group, viewer_id: nil,
                                                                  org_id: nil)

      expected_namespace = "news_feed.event.click"
      expected_payload = attributes["payload"] = {
        action_target: nil,
        user_id: nil,
        org_id: nil,
        originating_url: nil,
        event_group: @event_group,
        target_type: NewsFeedAnalytics::TARGET_TYPE_EVENT_GROUP,
        event: nil,
        feed_card: {
          card_retrieved_id: nil
        }
      }

      refute_nil attributes["hydro-click"]
      refute_nil attributes["hydro-click-hmac"]

      attrs_json = JSON.parse(attributes["hydro-click"]).deep_symbolize_keys
      assert_equal expected_namespace, attrs_json[:event_type]
      assert_equal expected_payload, attrs_json[:payload]
    end
  end

  context "#event_view_attributes" do
    test "returns with event" do
      attributes = NewsFeedAnalytics.event_view_attributes(@event, event_details: {},
                                                           viewer_id: nil, org_id: nil)

      expected_namespace = "news_feed.event.view"
      expected_payload = attributes["payload"] = {
        user_id: nil,
        org_id: nil,
        originating_url: nil,
        target_type: NewsFeedAnalytics::TARGET_TYPE_EVENT,
        event_group: nil,
        event: {
          repo_id: @repo.id,
          actor_id: @user.id,
          public: true,
          type: "WatchEvent",
          target_id: nil,
          id: nil,
        },
        feed_card: {
          card_retrieved_id: @event.retrieved_id,
        }
      }

      refute_nil attributes["hydro-view"]
      refute_nil attributes["hydro-view-hmac"]

      attrs_json = JSON.parse(attributes["hydro-view"]).deep_symbolize_keys
      assert_equal expected_namespace, attrs_json[:event_type]
      assert_equal expected_payload, attrs_json[:payload]
    end

    test "returns with event group" do
      attributes = NewsFeedAnalytics.event_group_view_attributes(@event_group, viewer_id: nil,
                                                                 org_id: nil)

      expected_namespace = "news_feed.event.view"
      expected_payload = attributes["payload"] = {
        user_id: nil,
        org_id: nil,
        originating_url: nil,
        target_type: NewsFeedAnalytics::TARGET_TYPE_EVENT_GROUP,
        event: nil,
        event_group: @event_group,
        feed_card: {
          card_retrieved_id: nil,
        },
      }

      refute_nil attributes["hydro-view"]
      refute_nil attributes["hydro-view-hmac"]

      attrs_json = JSON.parse(attributes["hydro-view"]).deep_symbolize_keys
      assert_equal expected_namespace, attrs_json[:event_type]
      assert_equal expected_payload, attrs_json[:payload]
    end
  end
end
