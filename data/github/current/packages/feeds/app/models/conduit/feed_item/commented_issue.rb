# typed: true
# frozen_string_literal: true

module Conduit
  class FeedItem::CommentedIssue < FeedItem
    delegate :repository, :issue, to: :issue_comment

    def issue_comment
      subject
    end

    # display
    def action_string
      "commented on an issue in"
    end

    def description
      "#{actor} #{action_string} in #{repository.name}"
    end

    # analytics
    def analytics_card_type
      CardType::ISSUE_COMMENTED
    end

    def resource_type
      ResourceType::ISSUE_COMMENT
    end

    def resource_id
      issue_comment.id
    end

    def issue_id
      issue.id
    end

    def source
      repository.name_with_display_owner
    end

    def self.supports_graphql?
      false
    end

    def api_type
      "IssueCommentEvent"
    end

    def payload
      {
        action: :created,
        issue: Api::Serializer.serialize(:issue_hash, issue_comment.issue),
        comment: Api::Serializer.serialize(:issue_comment_hash, issue_comment),
      }
    end
  end
end
