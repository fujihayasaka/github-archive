# typed: true
# frozen_string_literal: true

module Conduit
  class FeedItem::ClosedIssue < FeedItem::Issue
    # Display
    def action_string
      "closed an issue"
    end

    # Analytics
    def analytics_card_type
      CardType::ISSUE_CLOSED
    end

    def payload_action
      :closed
    end
  end
end
