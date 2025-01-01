# typed: true
# frozen_string_literal: true

require "test_helper"
require "monolith-twirp-conduit-feeds"

module Conduit
  class FeedItem::CreatedDiscussionTest < GitHub::TestCase
    fixtures do
      @discussion = create(:discussion)
      @viewer = create(:user)
    end

    setup do
      GitHub.flipper[:feeds_v2].disable
      @twirp_item = build(:twirp_conduit_discussion_feed_item, discussion: @discussion, gatherer: "gatherer")
      @actor = @discussion.user
      @feed_item = Conduit::FeedItem::CreatedDiscussion.new(
        @twirp_item,
        actor: @actor,
        subject: @discussion,
        viewer: @viewer,
      )
      @repository = @discussion.repository
    end

    context "#resource_id" do
      test "returns the repository ID" do
        assert_equal @repository.id, @feed_item.resource_id
      end
    end

    context "#resource_type" do
      test "returns REPO" do
        assert_equal "REPO", @feed_item.resource_type
      end
    end

    context "#subject" do
      test "returns discussion" do
        assert_equal @discussion, @feed_item.subject
      end
    end

    context "subject_id" do
      test "returns discussion ID" do
        assert_equal @discussion.id, @feed_item.subject_id
      end
    end

    context "#action_string" do
      test "is correct" do
        assert_equal "a new discussion in", @feed_item.action_string
      end

      test "feature flag enabled" do
        GitHub.flipper[:feeds_v2].enable
        assert_equal "a discussion in", @feed_item.action_string
      end
    end

    test "is a discussion event" do
      assert_predicate @feed_item, :discussion_event?
    end

    test  "is not a release event" do
      refute_predicate @feed_item, :release_event?
    end

    test "is not a user event" do
      refute_predicate @feed_item, :user_event?
    end

    test "is not a repo event" do
      refute_predicate @feed_item, :repo_event?
    end

    test "is not a newly sponsorable event" do
      refute_predicate @feed_item, :newly_sponsorable_event?
    end

    context "#analytics_card_type" do
      test "is correct" do
        assert_equal "NEW_DISCUSSION", @feed_item.analytics_card_type
      end
    end

    context "#analytics_attributes" do
      test "is correct" do
        expected_dimensions = {
          card_type: "NEW_DISCUSSION",
          resource_relationship: "followed",
          created_at: nil,
          record_id: @feed_item.subject_id,
          resource_type: "REPO",
          resource_id: @feed_item.resource_id,
          card_position: @feed_item.idx,
          card_sub_position: nil,
          card_retrieved_id: "",
          ranking_model_id: "",
          gatherer: "gatherer",
          variant: "{}",
          assignment_context: "",
        }

        assert_equal expected_dimensions, @feed_item.analytics_attributes
      end
    end

    context "description" do
      test "is correct" do
        assert_equal "#{@actor.login} created a new discussion in #{@discussion.category.name}",
          @feed_item.description
      end
    end

    context "universe_announcement?" do
      test "returns true for the universe announcement discussion" do
        @discussion.stubs(:id).returns(Conduit::FeedItem::CreatedDiscussion::UNIVERSE_DISCUSSION_ID)
        assert_equal true, @feed_item.universe_announcement?
      end

      test "returns false for other discussions" do
        @discussion.stubs(:id).returns(123)
        assert_equal false, @feed_item.universe_announcement?
      end
    end

    context "reason_message" do
      test "returns user follows org" do
        @feed_item.stubs(:reason).returns("followed")
        reason = @feed_item.reason_message
        assert_includes reason, "you follow #{@repository.owner.login}"
      end

      test "returns user stars repo" do
        @feed_item.stubs(:reason).returns("starred")
        reason = @feed_item.reason_message
        assert_includes reason, "you starred #{@repository.nwo}"
      end
    end
  end
end
