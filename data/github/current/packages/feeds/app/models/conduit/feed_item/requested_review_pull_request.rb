# typed: true
# frozen_string_literal: true

module Conduit
  class FeedItem::RequestedReviewPullRequest < FeedItem::PullRequest
    def payload
      super.merge(
        action: :requested,
      ).merge(requested_hash.deep_symbolize_keys)
    end

    def action_string
      if requested_team?
        "requested a review from a team"
      else
        "requested a review from a user"
      end
    end

    def analytics_card_type
      nil
    end

    private

    def requested_hash
      return {} if invalid_requested_review?

      if requested_team?
        team = Team.find_by(id: requested_subject_id)
        team ? { requested_team: ::Api::Serializer.serialize(:team_hash, team) } : {}
      else
        user = User.find_by(id: requested_subject_id)
        user ? { requested_reviewer: ::Api::Serializer.serialize(:user_hash, user) } : {}
      end
    end

    memoize def requested_subject_id
      requested_review.subject_id
    end

    memoize def requested_subject_type
      requested_review.subject_type
    end

    memoize def requested_review
      twirp_item.pull_request_subject.requested_review
    end

    def requested_team?
      requested_subject_type == :SUBJECT_TYPE_TEAM
    end

    def invalid_request_subject?
      requested_subject_type == :SUBJECT_TYPE_INVALID
    end

    def invalid_requested_review?
      return true unless requested_review.present?
      return true unless requested_review.subject_id.present?

      invalid_request_subject?
    end
  end
end
