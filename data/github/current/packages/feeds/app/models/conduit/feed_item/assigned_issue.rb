# typed: true
# frozen_string_literal: true

module Conduit
  class FeedItem::AssignedIssue < FeedItem::Issue
    def payload_action
      :assigned
    end

    # Analytics not required since this is not shown in the Feed
    def analytics_card_type
      nil
    end

    def payload
      super.merge(
        {
          assignee: assignees.last,
          assignees: assignees
        },
      )
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
      twirp_item.issue_subject.assignees.map(&:id)
    end
  end
end
