# typed: true
# frozen_string_literal: true

module Conduit
  class FeedItem::CreatedRepository < FeedItem
    GRAPHQL_TYPE = Platform::Objects::Conduit::CreatedRepositoryFeedItem

    def repository
      subject
    end

    # Display
    def action_string
      rollup? ? "created" : "created a repository"
    end

    def description
      "#{actor.login} created a repository"
    end

    # Analytics
    def analytics_card_type
      CardType::CREATED_REPOSITORY
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
