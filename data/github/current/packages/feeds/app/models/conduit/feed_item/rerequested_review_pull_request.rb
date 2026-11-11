# typed: true
# frozen_string_literal: true

module Conduit
  class FeedItem::RerequestedReviewPullRequest < FeedItem::RequestedReviewPullRequest
    def payload
      super.merge(
        rerequest: true,
      )
    end
  end
end
