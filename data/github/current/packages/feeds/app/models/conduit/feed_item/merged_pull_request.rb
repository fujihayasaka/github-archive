# typed: true
# frozen_string_literal: true

module Conduit
  class FeedItem::MergedPullRequest < FeedItem::PullRequest
    GRAPHQL_TYPE = Platform::Objects::Conduit::MergedPullRequestFeedItem

    # display
    def action_string
      "contributed to"
    end

    def description
      "#{actor} #{action_string} #{repository.name}"
    end

    # analytics
    def analytics_card_type
      CardType::MERGED_PULL_REQUEST
    end

    def self.supports_graphql?
      true
    end

    def payload_action
      :merged
    end
  end
end
