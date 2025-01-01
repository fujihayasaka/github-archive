# typed: true
# frozen_string_literal: true

module Conduit
  class FeedItem::PullRequestReview < FeedItem
    delegate :repository, to: :pull_request

    def pull_request_review
      subject
    end

    def api_type
      "PullRequestReviewEvent"
    end

    def payload
      {
        review: ::Api::Serializer.serialize(
          :pull_request_review_hash,
          pull_request_review,
          pull_request:,
          repo: repository,
          skip_author_association: true
        ),
        pull_request: ::Api::Serializer.serialize(pr_serialize_method, pull_request, repo: repository)
      }
    end

    def self.supports_graphql?
      false
    end

    # This FeedItem isn't being used for Feed Cards right now so doesn't need analytics
    def analytics_card_type
      nil
    end

    private

    memoize def pull_request
      feed&.pull_requests_by_id&.[](pull_request_review&.pull_request_id) || pull_request_review&.pull_request
    end
  end
end
