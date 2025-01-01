# typed: true
# frozen_string_literal: true

module Conduit
  class FeedItem::RepositoryRecommendation < FeedItem
    GRAPHQL_TYPE = Platform::Objects::Conduit::RepositoryRecommendationFeedItem
    L = {
      trending: "Trending on",
      based_on: "Based on",
      popular_on_gh: "Popular on GitHub",
      recommended: "Recommended for you"
    }.freeze

    def repository
      subject
    end

    # Display
    def action_string
      case reason
      when "trending"
        L[:trending]
      when "topics"
        L[:based_on]
      when "followed"
        "Popular projects among"
      when "popular"
        L[:popular_on_gh]
      when "viewed", "contributed", "starred", "other"
        L[:recommended]
      end
    end

    def description
      action_string
    end

    # Analytics
    def analytics_card_type
      CardType::REPOSITORY_RECOMMENDATION
    end

    def resource_type
      ResourceType::REPOSITORY
    end

    def resource_id
      repository.id
    end

    def action
      TwirpHelper.recommended_action
    end

    def reason
      relationship.downcase
    end

    def source
      repository.name_with_display_owner
    end
  end
end
