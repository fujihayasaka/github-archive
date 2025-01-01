# typed: true
# frozen_string_literal: true

module Conduit
  class FeedItem::SponsoredUser < FeedItem
    GRAPHQL_TYPE = Platform::Objects::Conduit::SponsoredUserFeedItem

    def sponsor
      actor
    end

    def sponsorable
      subject
    end

    # Display
    def action_string
      "sponsored"
    end

    def description
      "#{sponsor.login} sponsored #{sponsorable.login}"
    end

    # Analytics
    def analytics_card_type
      CardType::SPONSORED_USER
    end

    def resource_type
      ResourceType::USER
    end

    def resource_id
      sponsor.id
    end

    def source
      sponsorable.login
    end
  end
end
