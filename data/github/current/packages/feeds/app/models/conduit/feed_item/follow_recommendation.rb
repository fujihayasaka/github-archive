# typed: true
# frozen_string_literal: true

module Conduit
  class FeedItem::FollowRecommendation < FeedItem
    GRAPHQL_TYPE = Platform::Objects::Conduit::FollowRecommendationFeedItem

    def followee
      subject
    end

    def action_string
      "Recommended based on people you follow"
    end

    def description
      action_string
    end

    def analytics_card_type
      CardType::FOLLOW_RECOMMENDATION
    end

    def resource_type
      ResourceType::USER
    end

    def resource_id
      followee.id
    end

    def reason
      relationship.downcase
    end

    def source
      followee.login
    end
  end
end
