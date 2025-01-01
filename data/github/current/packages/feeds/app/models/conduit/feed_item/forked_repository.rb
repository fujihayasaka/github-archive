# typed: true
# frozen_string_literal: true

module Conduit
  class FeedItem::ForkedRepository < FeedItem::Repository
    GRAPHQL_TYPE = Platform::Objects::Conduit::ForkedRepositoryFeedItem

    # Display
    def action_string
      rollup? || Flipper[:feeds_v2].enabled?(@viewer) ? "forked" : "forked a repository"
    end

    def description
      "#{actor.login} forked a repository"
    end

    # Analytics
    def analytics_card_type
      CardType::FORKED_REPOSITORY
    end

    def api_type
      "ForkEvent"
    end

    def payload
      {
        action: :forked,
        forkee: Api::Serializer.serialize(:repository_hash, repository),
      }
    end
  end
end
