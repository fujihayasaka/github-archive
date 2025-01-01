# typed: true
# frozen_string_literal: true

module Conduit
  class FeedItem::CreatedPullRequestReviewComment < FeedItem
    delegate :created_at, to: :pull_request_review_comment
    delegate :repository, to: :pull_request

    def pull_request_review_comment
      subject
    end

    def api_type
      "PullRequestReviewCommentEvent"
    end

    def payload
      {
        action: :created,
        comment: serialized_comment,
        pull_request: ::Api::Serializer.serialize(pr_serialize_method, pull_request)
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

    def serialized_comment
      ::Api::Serializer.serialize review_comment_serialize_method, pull_request_review_comment,
        pull_request:, repo: repository
    end

    memoize def pull_request
      feed&.pull_requests_by_id&.[](pull_request_review_comment&.pull_request_id) ||
        pull_request_review_comment&.pull_request # domain-isolation-query-violation:ignore:packages/issues (SELECT)
    end

    def review_comment_serialize_method
      return :minimized_pull_request_review_comment_hash if minimized_payload?

      :pull_request_review_comment_hash
    end
  end
end
