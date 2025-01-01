# typed: true
# frozen_string_literal: true

module Conduit
  class FeedItem::UnrequestedReviewPullRequest < FeedItem::RequestedReviewPullRequest
    def payload
      super.merge(
        action: :review_request_removed,
      )
    end
  end
end
