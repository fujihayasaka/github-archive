# typed: true
# frozen_string_literal: true

module Conduit
  class FeedItem::MergedPullRequest < FeedItem
    delegate :repository, :issue, to: :pull_request

    GRAPHQL_TYPE = Platform::Objects::Conduit::MergedPullRequestFeedItem

    def pull_request
      subject
    end

    # display
    def action_string
      "contributed to"
    end

    def description
      "#{actor} #{action_string} #{repository.name}"
    end

    # analytics
    def analytics_card_type
      CardType::MERGED_PULL_REQUEST
    end

    def resource_type
      ResourceType::PULL_REQUEST
    end

    def resource_id
      pull_request.id
    end

    def issue_id
      issue.id
    end

    def source
      repository.nwo
    end
  end
end
