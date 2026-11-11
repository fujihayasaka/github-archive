# typed: strict
# frozen_string_literal: true

module PullRequests::PageData::ReviewSummaryComments
  class Payload
    class ReviewSummary < T::Struct
      const :id, String
      const :state, PullRequests::PageData::ReviewSummaryComments::Loader::ReviewState
      const :authorAssociation, String
      const :authorAvatarUrl, T.nilable(String)
      const :authorLogin, String
      const :body, String
      const :bodyHtml, String
      const :submittedAt, String
      const :isHidden, T::Boolean
      const :minimizedReason, T.nilable(String)
      const :onBehalfOf, T.nilable(String)
      const :reactionGroups, T::Array[PullRequests::PageData::Helpers::Reactable::Payload::ReactionGroup]
      const :repository, T.nilable(PullRequests::PageData::Helpers::Repository::Payload::Repository)
      const :url, String
      const :viewerCanReact, T::Boolean
    end

    sig do
      params(
        review_summaries: T::Array[PullRequests::PageData::ReviewSummaryComments::Loader::ReviewSummary]
      ).returns(T::Array[ReviewSummary])
    end
    def self.call(review_summaries)
      new.call(review_summaries)
    end

    sig do
      params(
        review_summaries: T::Array[PullRequests::PageData::ReviewSummaryComments::Loader::ReviewSummary]
      ).returns(T::Array[ReviewSummary])
    end
    def call(review_summaries)
      review_summaries.map do |review_summary|
        review = review_summary.review
        repository_payload = PullRequests::PageData::Helpers::Repository::Payload.build_repository(review.repository)

        ReviewSummary.new(
          id: review_summary.id,
          state: review_summary.state,
          authorAssociation: review_summary.author_association,
          authorAvatarUrl: review_summary.author_avatar_url,
          authorLogin: review_summary.author_login,
          body: review.body || "",
          bodyHtml: review_summary.body_html || "",
          submittedAt: (review.submitted_at || review.created_at).iso8601,
          isHidden: review.minimized?,
          minimizedReason: review.minimized_reason,
          onBehalfOf: review_summary.on_behalf_of_team_name,
          reactionGroups: PullRequests::PageData::Helpers::Reactable::Payload.build_reaction_groups(review_summary.reaction_groups),
          repository: repository_payload,
          url: review_summary.url,
          viewerCanReact: review_summary.viewer_can_react,
        )
      end
    end
  end
end
