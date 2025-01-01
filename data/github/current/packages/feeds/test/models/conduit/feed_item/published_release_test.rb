# typed: true
# frozen_string_literal: true

require "test_helper"
require "monolith-twirp-conduit-feeds"

module Conduit
  class FeedItem::PublishedReleaseTest < GitHub::TestCase
    fixtures do
      @repository = create(
        :repository,
        name: "bloop",
        owner: create(:user),
        from_example: :simple
      )
      @release = create(:release, repository: @repository)
      @actor = @release.author
    end

    setup do
      @twirp_item = build(:twirp_conduit_release_feed_item, release: @release)
      @feed_item = Conduit::FeedItem::PublishedRelease.new(@twirp_item, actor: @actor, subject: @release)
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
      test "returns release" do
        assert_equal @release, @feed_item.subject
      end
    end

    context "subject_id" do
      test "returns release ID" do
        assert_equal @release.id, @feed_item.subject_id
      end
    end

    context "#action_string" do
      test "is correct" do
        assert_equal "published a release", @feed_item.action_string
      end
    end

    test "is not a discussion event" do
      refute_predicate @feed_item, :discussion_event?
    end

    test  "is a release event" do
      assert_predicate @feed_item, :release_event?
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
        assert_equal "RELEASE", @feed_item.analytics_card_type
      end
    end

    context "#analytics_attributes" do
      test "is correct" do
        expected_dimensions = {
          card_type: "RELEASE",
          resource_relationship: "followed",
          created_at: nil,
          record_id: @feed_item.subject_id,
          resource_type: "REPO",
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

    context "description" do
      test "is correct" do
        assert_equal "#{@actor} published a release",
          @feed_item.description
      end
    end
  end
end
