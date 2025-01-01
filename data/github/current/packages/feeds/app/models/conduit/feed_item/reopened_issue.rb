# typed: true
# frozen_string_literal: true

module Conduit
  class FeedItem::ReopenedIssue < FeedItem::Issue
    # Display
    def action_string
      "reopened an issue"
    end

    # Analytics
    def analytics_card_type
      CardType::ISSUE_REOPENED
    end

    def payload_action
      :reopened
    end
  end
end
