# typed: true
# frozen_string_literal: true

module Conduit
  class FeedItem::CommentedPullRequest < FeedItem
    delegate :repository, :issue, to: :pull_request_comment

    def pull_request_comment
      subject
    end

    # display
    def action_string
      "commented on a pull request in"
    end

    def description
      "#{actor} #{action_string} #{repository.name}"
    end

    # analytics
    def analytics_card_type
      CardType::PULL_REQUEST_COMMENTED
    end

    def resource_type
      ResourceType::PULL_REQUEST_COMMENT
    end

    def resource_id
      pull_request_comment.id
    end

    def issue_id
      issue.id
    end

    def pull_request
      issue.pull_request
    end

    def source
      repository.name_with_display_owner
    end

    def self.supports_graphql?
      false
    end

    # We're preserving the Stratocaster naming for now
    def api_type
      "IssueCommentEvent"
    end

    def payload
      return unless issue

      {
        action: :created,
        issue: Api::Serializer.serialize(:issue_hash, issue),
        comment: Api::Serializer.serialize(:issue_comment_hash, pull_request_comment),
      }
    end
  end
end
