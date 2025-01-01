# typed: true
# frozen_string_literal: true

module Conduit
  class FeedItem::AssignedPullRequest < FeedItem::PullRequest
    def payload_action
      :assigned
    end

    def analytics_card_type
      nil
    end

    def payload
      super.merge(
        {
          assignee: assignees.last,
          assignees: assignees
        }
      )
    end

    def self.supports_graphql?
      false
    end

    private

    memoize def assignees
      User.where(id: assignee_ids).map do |assignee|
        Api::Serializer
          .serialize(:user_hash, assignee)
          .deep_symbolize_keys
      end
    end

    memoize def assignee_ids
      twirp_item.pull_request_subject.assignees.map(&:id)
    end
  end
end
