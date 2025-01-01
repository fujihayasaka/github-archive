# typed: true
# frozen_string_literal: true

require "test_helper"
require "monolith-twirp-conduit-feeds"

module Conduit
  class FeedItem::DismissedPullRequestReviewTest < GitHub::TestCase
    fixtures do
      @actor = create(:user, name: "doggo")
      @repo = create(:repository, owner: @actor, name: "woof", from_example: :review_comment_source)
      @pull_request = create(:pull_request, :with_mergeable_head, repository: @repo, user: @actor)
      @pull_request_review = create(:pull_request_review, pull_request: @pull_request, repository: @repo)
    end

    setup do
      twirp_item = build(:twirp_conduit_pull_request_review_feed_item,
        action: Conduit::TwirpHelper.closed_action,
        pull_request_review: @pull_request_review,
        actor_user: @actor)
      @feed_item = Conduit::FeedItem::DismissedPullRequestReview
        .new(twirp_item, actor: @actor, subject: @pull_request_review)
    end

    context "#pull_request_review" do
      test "returns pull_request_review" do
        assert_equal @pull_request_review, @feed_item.pull_request_review
      end
    end

    context "#payload" do
      test "it adds the right action" do
        assert_equal :dismissed, @feed_item.payload[:action]
      end
    end
  end
end
