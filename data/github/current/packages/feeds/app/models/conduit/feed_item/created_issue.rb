# typed: true
# frozen_string_literal: true

module Conduit
  class FeedItem::CreatedIssue < FeedItem::Issue
    # Display
    def action_string
      "opened an issue"
    end

    # Analytics
    def analytics_card_type
      CardType::ISSUE_CREATED
    end

    def payload_action
      :opened
    end
  end
end
