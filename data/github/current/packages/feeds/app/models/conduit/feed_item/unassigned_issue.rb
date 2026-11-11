# typed: true
# frozen_string_literal: true

module Conduit
  class FeedItem::UnassignedIssue < FeedItem::AssignedIssue
    def payload_action
      :unassigned
    end

    def action_string
      "unassigned an issue"
    end
  end
end
