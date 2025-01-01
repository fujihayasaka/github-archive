# typed: true
# frozen_string_literal: true

module Conduit
  class FeedItem::CreatedPullRequestReviewComment < FeedItem
    delegate :repository, to: :pull_request_review_comment

    def pull_request_review_comment
      subject
    end

    def api_type
      "PullRequestReviewCommentEvent"
    end

    def payload
      {
        action: :created,
        comment: Api::Serializer.serialize(:pull_request_review_comment_hash, pull_request_review_comment),
        pull_request: Api::Serializer.serialize(:pull_request_hash, pull_request_review_comment.pull_request)
      }
    end

    def self.supports_graphql?
      false
    end

    # This FeedItem isn't being used for Feed Cards right now so doesn't need analytics
    def analytics_card_type
      nil
    end
  end
end
