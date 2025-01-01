# typed: true
# frozen_string_literal: true

module Conduit
  class FeedItem::UnassignedIssue < FeedItem::AssignedIssue
    def payload_action
      :unassigned
    end
  end
end
