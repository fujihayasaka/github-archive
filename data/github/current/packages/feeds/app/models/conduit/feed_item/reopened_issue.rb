# typed: true
# frozen_string_literal: true

module Conduit
  class FeedItem::ReopenedIssue < FeedItem
    delegate :repository, to: :issue

    def issue
      subject
    end

    # Display
    def action_string
      "reopened an issue"
    end

    def description
      "#{actor} #{action_string} #{label.name} in #{repository.name}"
    end

    # Analytics
    def analytics_card_type
      CardType::ISSUE_REOPENED
    end

    def resource_type
      ResourceType::ISSUE
    end

    def resource_id
      issue.id
    end

    def source
      repository.name_with_display_owner
    end

    def self.supports_graphql?
      false
    end

    memoize def label
      issue.labels.where(name: ["good first issue", "help wanted"]).last
    end
  end
end
