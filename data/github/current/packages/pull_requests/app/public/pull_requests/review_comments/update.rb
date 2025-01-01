# typed: strict
# frozen_string_literal: true

module PullRequests
  module ReviewComments
    module Update
      module_function

      sig do
        params(
          comment: PullRequestReviewComment,
          body: String,
          user: User,
        ).returns(NilClass)
      end
      def update(comment:, body:, user:)
        GitHub.dogstats.distribution_time("pull_requests.review_comments.update", tags: ["review_comments:update"]) do
          comment.update_body(body, user)
        end
      end
    end
  end
end
