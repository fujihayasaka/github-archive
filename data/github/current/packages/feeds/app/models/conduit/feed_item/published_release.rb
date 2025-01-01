# typed: true
# frozen_string_literal: true

module Conduit
  class FeedItem::PublishedRelease < FeedItem
    delegate :repository, :tag_name, to: :release

    GRAPHQL_TYPE = Platform::Objects::Conduit::PublishedReleaseFeedItem

    def release
      subject
    end

    # Display
    def action_string
      "published a release"
    end

    def description
      "#{actor} published a release"
    end

    # Analytics
    def analytics_card_type
      CardType::PUBLISHED_RELEASE
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
