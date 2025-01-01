# typed: true
# frozen_string_literal: true

require "test_helper"
require "monolith-twirp-conduit-feeds"

module Conduit
  class FeedItem::FollowRecommendationTest < GitHub::TestCase

    fixtures do
      @followee = create(:user)
    end

    setup do
      @twirp_item = build(:twirp_conduit_user_feed_item,
        actor_user: @followee,
        subject_user: @followee,
        action: Conduit::TwirpHelper.recommended_action
      )
      @feed_item = Conduit::FeedItem::FollowRecommendation.new(
        @twirp_item,
        actor: @followee,
        subject: @followee,
      )
    end

    context "#resource_id" do
      test "returns the followee ID" do
        assert_equal @followee.id, @feed_item.resource_id
      end
    end

    context "#resource_type" do
      test "returns USER" do
        assert_equal "USER", @feed_item.resource_type
      end
    end

    context "#subject" do
      test "returns followee" do
        assert_equal @followee, @feed_item.subject
      end
    end

    context "subject_id" do
      test "returns followee ID" do
        assert_equal @followee.id, @feed_item.subject_id
      end
    end

    context "#action_string" do
      test "is correct" do
        assert_equal "Recommended based on people you follow", @feed_item.action_string
      end
    end

    context "description" do
      test "is correct" do
        assert_equal "Recommended based on people you follow", @feed_item.description
      end
    end

    context "#analytics_card_type" do
      test "is correct" do
        assert_equal "FOLLOW_RECOMMENDATION", @feed_item.analytics_card_type
      end
    end

    context "#analytics_attributes" do
      test "is correct" do
        expected_dimensions = {
          card_type: "FOLLOW_RECOMMENDATION",
          resource_relationship: "followed",
          created_at: nil,
          record_id: @feed_item.subject_id,
          resource_type: ::Conduit::AnalyticsHelper::ResourceType::USER,
          resource_id: @feed_item.resource_id,
          card_position: nil,
          card_sub_position: nil,
          card_retrieved_id: "",
          ranking_model_id: "",
          gatherer: "",
          variant: "{}",
          assignment_context: "",
        }

        assert_equal expected_dimensions, @feed_item.analytics_attributes
      end
    end

    test "is not a discussion event" do
      refute_predicate @feed_item, :discussion_event?
    end

    test  "is not a release event" do
      refute_predicate @feed_item, :release_event?
    end

    test "is not a user event" do
      refute_predicate @feed_item, :user_event?
    end

    test "is not a newly sponsorable event" do
      refute_predicate @feed_item, :newly_sponsorable_event?
    end

    test "is not a repo event" do
      refute_predicate @feed_item, :repo_event?
    end

    test "is not a near sponsors goal event" do
      refute_predicate @feed_item, :near_sponsors_goal_event?
    end

    test "is a follow recommendation event" do
      assert_predicate @feed_item, :follow_recommendation_event?
    end
  end
end
