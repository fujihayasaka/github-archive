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

    def action_string
      "assigned a pull request"
    end

    private

    memoize def assignees
      assignee_records.map do |assignee|
        ::Api::Serializer
          .serialize(:user_hash, assignee)
          .deep_symbolize_keys
      end
    end

    memoize def assignee_records
      return [] if assignee_ids.empty?
      return cached_assignees if cached_assignees.any?

      User.where(id: assignee_ids)
    end

    memoize def cached_assignees
      return [] unless feed
      return [] unless feed.cached_records[:assignees].present?

      feed.cached_records[:assignees].select do |assignee|
        assignee_ids.include?(assignee.id)
      end
    end

    memoize def assignee_ids
      twirp_item.pull_request_subject.assignees.map(&:id)
    end
  end
end
