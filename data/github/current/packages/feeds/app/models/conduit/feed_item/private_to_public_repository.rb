# typed: true
# frozen_string_literal: true

module Conduit
  class FeedItem::PrivateToPublicRepository < FeedItem::Repository
    def made_public_at
      subject.made_public_at
    end

    def action
      TwirpHelper.published_action
    end

    def action_string
      "made this repository public"
    end

    def description
      "#{actor.display_login} #{action_string}"
    end

    # Analytics
    def analytics_card_type
      CardType::PRIVATE_TO_PUBLIC_REPOSITORY
    end

    def reason
      relationship.downcase
    end

    def self.supports_graphql?
      false
    end

    def api_type
      "PublicEvent"
    end
  end
end
