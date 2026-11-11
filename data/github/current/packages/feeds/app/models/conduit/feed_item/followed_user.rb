# typed: true
# frozen_string_literal: true

module Conduit
  class FeedItem::FollowedUser < FeedItem
    GRAPHQL_TYPE = Platform::Objects::Conduit::FollowedUserFeedItem

    def follower
      actor
    end

    def followee
      subject
    end

    # Display
    def action_string
      subject_is_viewer? ? "started following" : "followed"
    end

    def description
      "#{follower.display_login} followed #{followee.display_login}"
    end

    # Analytics
    def analytics_card_type
      CardType::FOLLOWED_USER
    end

    def resource_type
      ResourceType::USER
    end

    def resource_id
      follower.id
    end

    def source
      followee.display_login
    end
  end
end
