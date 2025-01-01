# typed: true
# frozen_string_literal: true

module Conduit
  class FeedItem::MemberAddToRepository < FeedItem
    GRAPHQL_TYPE = Platform::Objects::Conduit::MemberAddToRepositoryFeedItem

    delegate :name, to: :repository

    def repository
      subject.repository
    end

    def member
      subject.member
    end

    # Display
    def action_string
      rollup? ? "added #{total_related_items + 1} members to" : "added"
    end

    def description
      "#{actor.display_login} added #{member.display_login} to #{repository.name_with_display_owner}"
    end

    # Analytics
    def analytics_card_type
      CardType::MEMBER_ADD_TO_REPO
    end

    def resource_type
      ResourceType::REPOSITORY
    end

    def resource_id
      repository.id
    end

    def subject_id
      nil
    end

    def source
      repository.name_with_display_owner
    end

    def api_type
      "MemberEvent"
    end

    def payload
      {
        member: Api::Serializer.serialize(:user_hash, member),
        action: :added
      }
    end
  end
end
