# typed: true
# frozen_string_literal: true

module Conduit
  class FeedItem::CreatedRepository < FeedItem::Repository
    GRAPHQL_TYPE = Platform::Objects::Conduit::CreatedRepositoryFeedItem

    # Display
    def action_string
      rollup? ? "created" : "created a repository"
    end

    def description
      "#{actor.display_login} created a repository"
    end

    # Analytics
    def analytics_card_type
      CardType::CREATED_REPOSITORY
    end

    def payload
      super.merge({
        action: :created,
      })
    end
  end
end
