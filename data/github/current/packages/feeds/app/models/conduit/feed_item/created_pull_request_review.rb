# typed: true
# frozen_string_literal: true

module Conduit
  class FeedItem::CreatedPullRequestReview < FeedItem::PullRequestReview
    def payload
      super.merge(
        action: :created,
      )
    end
  end
end
