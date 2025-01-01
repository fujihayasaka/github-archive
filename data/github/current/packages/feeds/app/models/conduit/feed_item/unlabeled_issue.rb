# typed: true
# frozen_string_literal: true

module Conduit
  class FeedItem::UnlabeledIssue < FeedItem::LabeledIssue
    def payload_action
      :unlabeled
    end

    # Analytics not required since this is not shown in the Feed
    def analytics_card_type
      nil
    end
  end
end
