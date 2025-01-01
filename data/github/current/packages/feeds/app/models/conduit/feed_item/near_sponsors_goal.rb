# typed: true
# frozen_string_literal: true

module Conduit
  class FeedItem::NearSponsorsGoal < FeedItem
    GRAPHQL_TYPE = Platform::Objects::Conduit::NearSponsorsGoalFeedItem

    def sponsorable
      actor
    end

    def action_string
      "is close to reaching their goal"
    end

    def description
      "#{sponsorable} #{action_string}"
    end

    def analytics_card_type
      CardType::NEAR_SPONSORS_GOAL
    end

    def resource_type
      ResourceType::USER
    end

    def resource_id
      sponsorable.id
    end

    def source
      actor.display_login
    end
  end
end
