# typed: true
# frozen_string_literal: true

require "test_helper"
require "monolith-twirp-conduit-feeds"

module Conduit
  class FeedItem::NearSponsorsGoalTest < GitHub::TestCase
    fixtures do
      @sponsorable = create(:user, :sponsorable)
      @goal = create(:sponsors_goal, :active, listing: @sponsorable.sponsors_listing)
    end

    setup do
      @twirp_item = build(:twirp_conduit_user_feed_item,
        actor_user: @sponsorable,
        subject_user: @sponsorable,
        action: Conduit::TwirpHelper.near_sponsors_goal_action
      )
      @feed_item = Conduit::FeedItem::NearSponsorsGoal.new(
        @twirp_item,
        actor: @sponsorable,
        subject: @sponsorable)
    end

    context "#resource_id" do
      test "returns the sponsorable ID" do
        assert_equal @sponsorable.id, @feed_item.resource_id
      end
    end

    context "#resource_type" do
      test "returns USER" do
        assert_equal "USER", @feed_item.resource_type
      end
    end

    context "#subject" do
      test "returns sponsorable" do
        assert_equal @sponsorable, @feed_item.subject
      end
    end

    context "subject_id" do
      test "returns sponsorable ID" do
        assert_equal @sponsorable.id, @feed_item.subject_id
      end
    end

    context "#action_string" do
      test "is correct" do
        assert_equal "is close to reaching their goal", @feed_item.action_string
      end
    end

    context "description" do
      test "is correct" do
        assert_equal "#{@sponsorable} is close to reaching their goal", @feed_item.description
      end
    end

    context "#analytics_card_type" do
      test "is correct" do
        assert_equal "NEAR_SPONSORS_GOAL", @feed_item.analytics_card_type
      end
    end

    context "#analytics_attributes" do
      test "is correct" do
        expected_dimensions = {
          card_type: "NEAR_SPONSORS_GOAL",
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

    test "is a near sponsors goal event" do
      assert_predicate @feed_item, :near_sponsors_goal_event?
    end
  end
end
