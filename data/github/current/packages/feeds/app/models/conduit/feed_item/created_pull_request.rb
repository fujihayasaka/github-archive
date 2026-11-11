# typed: true
# frozen_string_literal: true

module Conduit
  class FeedItem::CreatedPullRequest < FeedItem::PullRequest
    # display
    def action_string
      "opened a pull request"
    end

    # analytics
    def analytics_card_type
      CardType::CREATED_PULL_REQUEST
    end

    def payload_action
      :opened
    end
  end
end
