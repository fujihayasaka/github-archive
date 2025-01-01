# typed: true
# frozen_string_literal: true

module Conduit
  class FeedItem::ClosedPullRequest < FeedItem::PullRequest
    # display
    def action_string
      "closed a pull request"
    end

    # analytics
    def analytics_card_type
      CardType::CLOSED_PULL_REQUEST
    end

    def payload_action
      :closed
    end
  end
end
