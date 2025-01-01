# typed: true
# frozen_string_literal: true

module Conduit
  class FeedItem::UnlabeledPullRequest < FeedItem::LabeledPullRequest
    def analytics_card_type
      nil
    end

    def payload_action
      :unlabeled
    end
  end
end
