# typed: true
# frozen_string_literal: true

module Conduit
  class FeedItem::UnassignedPullRequest < FeedItem::AssignedPullRequest
    def payload_action
      :unassigned
    end

    def analytics_card_type
      nil
    end
  end
end
