# typed: true
# frozen_string_literal: true

module Conduit
  class FeedItem::ReopenedPullRequest < FeedItem::PullRequest
    # display
    def action_string
      "reopened a pull request"
    end

    # analytics
    def analytics_card_type
      CardType::REOPENED_PULL_REQUEST
    end

    def payload_action
      :reopened
    end
  end
end
