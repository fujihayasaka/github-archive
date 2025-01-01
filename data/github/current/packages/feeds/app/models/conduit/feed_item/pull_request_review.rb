# typed: true
# frozen_string_literal: true

module Conduit
  class FeedItem::PullRequestReview < FeedItem
    delegate :repository, to: :pull_request_review

    def pull_request_review
      subject
    end

    def api_type
      "PullRequestReviewEvent"
    end

    def payload
      {
        review: Api::Serializer.serialize(:pull_request_review_hash, pull_request_review),
        pull_request: Api::Serializer.serialize(:pull_request_hash, pull_request_review.pull_request)
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
