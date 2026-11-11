# typed: strict
# frozen_string_literal: true

module PullRequests::PageData::Overview::Reviewers
  class Payload
    class ReviewerPayload < T::Struct
      const :id, Integer
      const :displayLogin, String
      const :name, T.nilable(String)
      const :avatarUrl, String
      const :reviewerType, PullRequests::PageData::Overview::ReviewRequests::Loader::ReviewerType
      const :organizationLogin, T.nilable(String)
    end

    class ReviewersPayload < T::Struct
      # The filtered set of users and teams a viewer may request a review from.
      const :availableReviewers, T::Array[ReviewerPayload]
    end

    sig do
      params(
        reviewers_data: PullRequests::PageData::Overview::Reviewers::Loader::ReviewersData,
      ).returns(ReviewersPayload)
    end
    def self.call(reviewers_data)
      new(reviewers_data:).call
    end

    sig do
      params(
        reviewers_data: PullRequests::PageData::Overview::Reviewers::Loader::ReviewersData,
      ).void
    end
    def initialize(reviewers_data:)
      @reviewers_data = reviewers_data
    end

    sig { returns(ReviewersPayload) }
    def call
      ReviewersPayload.new(
        availableReviewers: @reviewers_data.available_reviewers.map { |r| build_reviewer_payload(r) },
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
  end
end
