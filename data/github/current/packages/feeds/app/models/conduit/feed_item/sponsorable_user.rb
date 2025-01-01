# typed: true
# frozen_string_literal: true

module Conduit
  class FeedItem::SponsorableUser < FeedItem
    GRAPHQL_TYPE = Platform::Objects::Conduit::BecameSponsorableFeedItem

    def sponsorable
      actor
    end

    # Display
    def action_string
      "launched their sponsorship page 💖"
    end

    def description
      "#{sponsorable.display_login} launched their sponsorship page 💖"
    end

    # Analytics
    def analytics_card_type
      CardType::SPONSORABLE_USER
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
