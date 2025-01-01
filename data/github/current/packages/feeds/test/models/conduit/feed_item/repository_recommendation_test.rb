# typed: true
# frozen_string_literal: true

require "test_helper"
require "monolith-twirp-conduit-feeds"

module Conduit
  class FeedItem::RepositoryRecommendationTest < GitHub::TestCase
    fixtures do
      @repository = create(:repository)
    end

    setup do
      @twirp_item = build(
        :twirp_conduit_repository_feed_item,
        repository: @repository,
        action: Conduit::TwirpHelper.recommended_action,
      )
      @feed_item = Conduit::FeedItem::RepositoryRecommendation.new(
        @twirp_item,
        actor: @repository.owner,
        subject: @repository
      )
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
      test "returns repository" do
        assert_equal @repository, @feed_item.subject
      end
    end

    context "subject_id" do
      test "returns repository ID" do
        assert_equal @repository.id, @feed_item.subject_id
      end
    end

    context "#action_string" do
      test "is correct for `followed` reason with new design" do
        GitHub.flipper[:feeds_v2].enable
        assert_equal "Popular projects among", @feed_item.action_string
      end

      test "is correct for `followed` reason" do
        GitHub.flipper[:feeds_v2].disable
        assert_equal "Popular among", @feed_item.action_string
      end

      test "is correct for `trending` reason" do
        twirp_item = build(
          :twirp_conduit_repository_feed_item,
          repository: @repository,
          action: Conduit::TwirpHelper.recommended_action,
          relationship: "trending"
        )
        feed_item = Conduit::FeedItem::RepositoryRecommendation.new(
          twirp_item,
          actor: @repository.owner,
          subject: @repository
        )
        assert_equal "Trending on", feed_item.action_string
      end

      test "is correct for `topics` reason" do
        twirp_item = build(
          :twirp_conduit_repository_feed_item,
          repository: @repository,
          action: Conduit::TwirpHelper.recommended_action,
          relationship: "topics"
        )
        feed_item = Conduit::FeedItem::RepositoryRecommendation.new(
          twirp_item,
          actor: @repository.owner,
          subject: @repository
        )
        assert_equal "Based on", feed_item.action_string
      end

      test "is correct for `popular` reason" do
        twirp_item = build(
          :twirp_conduit_repository_feed_item,
          repository: @repository,
          action: Conduit::TwirpHelper.recommended_action,
          relationship: "popular"
        )
        feed_item = Conduit::FeedItem::RepositoryRecommendation.new(
          twirp_item,
          actor: @repository.owner,
          subject: @repository
        )
        assert_equal "Popular on GitHub", feed_item.action_string
      end

      test "is correct for `contributed`, `starred`, `other` reason" do
        %w[contributed starred other].each do |relationship|
          twirp_item = build(
            :twirp_conduit_repository_feed_item,
            repository: @repository,
            action: Conduit::TwirpHelper.recommended_action,
            relationship: relationship
          )
          feed_item = Conduit::FeedItem::RepositoryRecommendation.new(
            twirp_item,
            actor: @repository.owner,
            subject: @repository
          )
          assert_equal "Recommended for you", feed_item.action_string
        end
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

    test "is a repo event" do
      assert_predicate @feed_item, :repo_event?
    end

    test "is not a newly sponsorable event" do
      refute_predicate @feed_item, :newly_sponsorable_event?
    end

    context "#analytics_card_type" do
      test "is correct" do
        assert_equal "REPOSITORY_RECOMMENDATION", @feed_item.analytics_card_type
      end
    end

    context "#analytics_attributes" do
      test "is correct" do
        expected_dimensions = {
          card_type: "REPOSITORY_RECOMMENDATION",
          resource_relationship: "followed",
          created_at: nil,
          record_id: @feed_item.subject_id,
          resource_type: ::Conduit::AnalyticsHelper::ResourceType::REPOSITORY,
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
        assert_equal @feed_item.action_string, @feed_item.description
      end
    end
  end
end
