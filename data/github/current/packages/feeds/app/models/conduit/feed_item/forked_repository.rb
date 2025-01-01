# typed: true
# frozen_string_literal: true

module Conduit
  class FeedItem::ForkedRepository < FeedItem
    GRAPHQL_TYPE = Platform::Objects::Conduit::ForkedRepositoryFeedItem

    def repository
      subject
    end

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

    def resource_type
      ResourceType::REPOSITORY
    end

    def resource_id
      repository.id
    end

    def source
      repository.nwo
    end
  end
end
