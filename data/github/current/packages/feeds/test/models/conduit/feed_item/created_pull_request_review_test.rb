# typed: true
# frozen_string_literal: true

require "test_helper"
require "monolith-twirp-conduit-feeds"

module Conduit
  class FeedItem::CreatedPullRequestReviewTest < GitHub::TestCase
    fixtures do
      @actor = create(:user, name: "doggo")
      @repo = create(:repository, owner: @actor, name: "woof", from_example: :review_comment_source)
      @pull_request = create(:pull_request, :with_mergeable_head, repository: @repo, user: @actor)
      @pull_request_review = create(:pull_request_review, pull_request: @pull_request, repository: @repo)
    end

    setup do
      twirp_item = build(:twirp_conduit_pull_request_review_feed_item,
        action: Conduit::TwirpHelper.published_action,
        pull_request_review: @pull_request_review,
        actor_user: @actor)
      @feed_item = Conduit::FeedItem::CreatedPullRequestReview.new(twirp_item, actor: @actor, subject: @pull_request_review)
    end

    context "#pull_request_review" do
      test "returns pull_request_review" do
        assert_equal @pull_request_review, @feed_item.pull_request_review
      end
    end

    context "#analytics_card_type" do
      test "returns nil" do
        assert_nil @feed_item.analytics_card_type
      end
    end

    context ".supports_graphql?" do
      test "returns false" do
        assert_equal false, Conduit::FeedItem::CreatedPullRequestReview.supports_graphql?
      end
    end

    context "#payload" do
      test "it adds the right action" do
        assert_equal :created, @feed_item.payload[:action]
      end
    end
  end
end
