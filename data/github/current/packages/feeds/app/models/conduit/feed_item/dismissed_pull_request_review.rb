# typed: true
# frozen_string_literal: true

module Conduit
  class FeedItem::DismissedPullRequestReview < FeedItem::PullRequestReview
    def payload
      super.merge(
        action: :dismissed,
      )
    end
  end
end
