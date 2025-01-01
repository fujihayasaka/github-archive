# typed: true
# frozen_string_literal: true

require "test_helper"
require "monolith-twirp-conduit-feeds"

module Conduit
  class FeedItem::CreatedPullRequestReviewCommentTest < GitHub::TestCase
    fixtures do
      @actor = create(:user, name: "doggo")
      @repo = create(:repository, owner: @actor, name: "woof", from_example: :review_comment_source)
      @pull_request = create(:pull_request, :with_mergeable_head, repository: @repo, user: @actor)
      @pull_request_review_comment = create(:pull_request_review_comment, pull_request: @pull_request, repository: @repo)
    end

    setup do
      @twirp_item = build(:twirp_conduit_pull_request_review_comment_feed_item,
        action: Conduit::TwirpHelper.published_action,
        pull_request_review_comment: @pull_request_review_comment,
        actor_user: @actor)
      @feed_item = Conduit::FeedItem::CreatedPullRequestReviewComment.new(
        @twirp_item,
        actor: @actor,
        subject: @pull_request_review_comment
      )
    end

    context "feed" do
      test "returns item in the feed" do
        feed = Conduit::Feed.new(@actor, viewer: @actor, twirp_items: [@twirp_item])
        refute_empty feed.build.items
      end
    end

    context "#pull_request_review_comment" do
      test "returns pull_request_review_comment" do
        assert_equal @pull_request_review_comment, @feed_item.pull_request_review_comment
      end
    end

    context "#analytics_card_type" do
      test "returns nil" do
        assert_nil @feed_item.analytics_card_type
      end
    end

    context ".supports_graphql?" do
      test "returns false" do
        assert_equal false, Conduit::FeedItem::CreatedPullRequestReviewComment.supports_graphql?
      end
    end
  end
end
