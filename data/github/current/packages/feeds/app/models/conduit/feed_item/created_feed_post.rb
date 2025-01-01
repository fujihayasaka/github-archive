# typed: true
# frozen_string_literal: true

module Conduit
  class FeedItem::CreatedFeedPost < FeedItem
    delegate :author, :owner, :topic, to: :feed_post

    def feed_post
      subject
    end

    # Display
    def action_string
      "a new post"
    end

    def description
      "#{actor.display_login} published a new post"
    end

    # Analytics
    def analytics_card_type
      CardType::CREATED_FEED_POST
    end

    def resource_type
      ResourceType::FEED_POST
    end

    def resource_id
      feed_post.id
    end

    def source
      owner.display_login
    end

    def self.supports_graphql?
      false
    end
  end
end
