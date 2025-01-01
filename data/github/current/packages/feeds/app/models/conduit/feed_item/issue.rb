# typed: true
# frozen_string_literal: true

module Conduit
  class FeedItem::Issue < FeedItem
    delegate :repository, to: :issue

    def issue
      subject
    end

    def api_type
      "IssuesEvent"
    end

    def description
      "#{actor} #{action_string} in #{repository.name}"
    end

    def self.supports_graphql?
      false
    end

    def resource_type
      ResourceType::ISSUE
    end

    def resource_id
      issue.id
    end

    memoize def label
      issue.labels.where(name: ["good first issue", "help wanted"]).last
    end

    def source
      repository.name_with_display_owner
    end

    def payload
      {
        action: payload_action,
        issue: ::Api::Serializer.serialize(:issue_hash, issue),
      }
    end

    private

    def payload_action
      nil
    end
  end
end
