# typed: true
# frozen_string_literal: true

module Conduit
  class FeedItem::CommentedCommit < FeedItem
    delegate :repository, to: :comment

    def comment
      subject
    end

    def api_type
      "CommitCommentEvent"
    end

    def payload
      {
        action: :created,
        comment: ::Api::Serializer.serialize(commit_comment_serialize_method, comment)
      }
    end

    def self.supports_graphql?
      false
    end

    # Analytics not required since this is not shown in the Feed
    def analytics_card_type
      nil
    end

    private

    def commit_comment_serialize_method
      return :minimized_commit_comment_hash if minimized_payload?

      :commit_comment_hash
    end
  end
end
