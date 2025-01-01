# typed: true
# frozen_string_literal: true

module Conduit
  class FeedItem::StarredRepository < FeedItem
    GRAPHQL_TYPE = Platform::Objects::Conduit::StarredRepositoryFeedItem

    def repository
      subject
    end

    # Display
    def action_string
      "starred"
    end

    def description
      "#{actor.login} starred #{repository}"
    end

    # Analytics
    def analytics_card_type
      CardType::STARRED_REPOSITORY
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
