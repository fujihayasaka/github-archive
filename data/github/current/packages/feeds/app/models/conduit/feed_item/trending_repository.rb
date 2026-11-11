# typed: true
# frozen_string_literal: true

module Conduit
  class FeedItem::TrendingRepository < FeedItem
    def repository
      subject
    end

    # Display
    def action_string
      "Trending repositories"
    end

    # Analytics
    def analytics_card_type
      CardType::TRENDING_REPOSITORY
    end

    def resource_type
      ResourceType::REPOSITORY
    end

    def resource_id
      repository.id
    end

    def source
      repository.name_with_display_owner
    end

    def self.supports_graphql?
      false
    end

    def reason
      "trending"
    end

    def reason_message
      SUBJECT_REASON[:trending]
    end
  end
end
