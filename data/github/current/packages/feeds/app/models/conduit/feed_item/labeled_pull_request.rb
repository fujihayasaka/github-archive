# typed: true
# frozen_string_literal: true

module Conduit
  class FeedItem::LabeledPullRequest < FeedItem::PullRequest
    delegate :repository, :issue, to: :pull_request

    def pull_request
      subject
    end

    # display
    def action_string
      "labeled a pull request"
    end

    def description
      "#{actor} #{action_string} #{label.name} in #{repository.name}"
    end

    # analytics
    def analytics_card_type
      CardType::LABELED_PULL_REQUEST
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
      repository.name_with_display_owner
    end

    def self.supports_graphql?
      false
    end

    memoize def label
      pull_request.labels.where(name: ["good first issue", "help wanted"]).last
    end

    def action
      :labeled
    end
  end
end
