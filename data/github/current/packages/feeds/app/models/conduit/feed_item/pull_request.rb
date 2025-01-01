# typed: true
# frozen_string_literal: true

module Conduit
  class FeedItem::PullRequest < FeedItem
    delegate :repository, :issue, to: :pull_request

    def pull_request
      subject
    end

    def description
      "#{actor} #{action_string} in #{repository.name}"
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

    memoize def label
      pull_request.labels.where(name: ["good first issue", "help wanted"]).last
    end

    def api_type
      "PullRequestEvent"
    end

    def source
      repository.name_with_display_owner
    end

    def self.supports_graphql?
      false
    end

    def payload
      {
        action: payload_action,
        number: pull_request.number,
        pull_request: ::Api::Serializer.serialize(:pull_request_hash, pull_request, full: true)
      }
    end

    private

    def payload_action
      nil
    end
  end
end
