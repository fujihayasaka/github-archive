# typed: true
# frozen_string_literal: true

module Conduit
  class FeedItem::AddedToList < FeedItem
    GRAPHQL_TYPE = Platform::Objects::Conduit::AddedToListFeedItem

    def repository
      subject.repository
    end

    def user_list
      subject.user_list
    end

    # Display
    def action_string
      rollup? ? "added #{total_related_items + 1} repositories to" : "added a repository to"
    end

    def description
      "#{actor.login} added a repository to #{user_list.name}"
    end

    # Analytics
    def analytics_card_type
      CardType::ADDED_TO_LIST
    end

    def resource_type
      ResourceType::REPOSITORY
    end

    def resource_id
      subject.repository.id
    end

    def subject_id
      subject.user_list.id
    end

    def source
      repository.nwo
    end
  end
end
