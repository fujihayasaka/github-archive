# typed: true
# frozen_string_literal: true

module Conduit
  class FeedItem::UpdatedPullRequestReview < FeedItem::PullRequestReview
    def payload
      super.merge(
        action: :updated,
      )
    end
  end
end
