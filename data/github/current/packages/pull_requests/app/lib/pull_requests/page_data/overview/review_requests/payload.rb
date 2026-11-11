# typed: strict
# frozen_string_literal: true

module PullRequests::PageData::Overview::ReviewRequests
  class Payload
    class ReviewerPayload < T::Struct
      const :id, Integer
      const :displayLogin, String
      const :name, T.nilable(String)
      const :avatarUrl, String
      const :reviewerType, String
      const :organizationLogin, T.nilable(String)
    end

    class PendingReviewRequestPayload < T::Struct
      const :reviewer, ReviewerPayload
      const :isCodeOwner, T::Boolean
      const :isCodeOwnerFromDelegation, T::Boolean
      const :deferredType, T.nilable(String)
      const :delegatedFromTeamName, T.nilable(String)
    end

    class CompletedReviewPayload < T::Struct
      const :reviewer, ReviewerPayload
      const :state, String
      const :headSha, String
      const :hasWriteAccess, T::Boolean
      const :canReRequest, T::Boolean
    end

    class SuggestedReviewerPayload < T::Struct
      const :reviewer, ReviewerPayload
      const :description, String
    end

    class ReviewersPayload < T::Struct
      const :pendingReviewRequests, T::Array[PendingReviewRequestPayload]
      const :completedReviews, T::Array[CompletedReviewPayload]
      const :suggestedReviewers, T::Array[SuggestedReviewerPayload]
    end

    sig do
      params(
        reviewers_data: PullRequests::PageData::Overview::ReviewRequests::Loader::ReviewersData,
      ).returns(ReviewersPayload)
    end
    def self.call(reviewers_data)
      new(reviewers_data:).call
    end

    sig do
      params(
        reviewers_data: PullRequests::PageData::Overview::ReviewRequests::Loader::ReviewersData,
      ).void
    end
    def initialize(reviewers_data:)
      @reviewers_data = reviewers_data
    end

    sig { returns(ReviewersPayload) }
    def call
      ReviewersPayload.new(
        pendingReviewRequests: @reviewers_data.pending_review_requests.map { |r| build_pending_review_request(r) },
        completedReviews: @reviewers_data.completed_reviews.map { |r| build_completed_review(r) },
        suggestedReviewers: @reviewers_data.suggested_reviewers.map { |s| build_suggested_reviewer(s) },
      )
    end

    private

    sig { params(reviewer_data: Loader::ReviewerData).returns(ReviewerPayload) }
    def build_reviewer_payload(reviewer_data)
      ReviewerPayload.new(
        id: reviewer_data.id,
        displayLogin: reviewer_data.display_login,
        name: reviewer_data.name,
        avatarUrl: reviewer_data.avatar_url,
        reviewerType: reviewer_data.reviewer_type,
        organizationLogin: reviewer_data.organization_login,
      )
    end

    sig { params(data: Loader::PendingReviewRequestData).returns(PendingReviewRequestPayload) }
    def build_pending_review_request(data)
      PendingReviewRequestPayload.new(
        reviewer: build_reviewer_payload(data.reviewer),
        isCodeOwner: data.is_code_owner,
        isCodeOwnerFromDelegation: data.is_code_owner_from_delegation,
        deferredType: data.deferred_type,
        delegatedFromTeamName: data.delegated_from_team_name,
      )
    end

    sig { params(data: Loader::CompletedReviewData).returns(CompletedReviewPayload) }
    def build_completed_review(data)
      CompletedReviewPayload.new(
        reviewer: build_reviewer_payload(data.reviewer),
        state: data.state,
        headSha: data.head_sha,
        hasWriteAccess: data.has_write_access,
        canReRequest: data.can_re_request,
      )
    end

    sig { params(data: Loader::SuggestedReviewerData).returns(SuggestedReviewerPayload) }
    def build_suggested_reviewer(data)
      SuggestedReviewerPayload.new(
        reviewer: build_reviewer_payload(data.reviewer),
        description: data.description,
      )
    end
  end
end
