# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    class LatestNonPendingPullRequestReview < Platform::Loader
      def self.load(pull_request_id, user_id)
        self.for.load([pull_request_id, user_id])
      end

      def fetch(pull_request_and_user_ids)
        conditions = pull_request_and_user_ids.map do |_, _|
          "(`pull_request_reviews`.`pull_request_id` = ? AND `pull_request_reviews`.`user_id` = ?)"
        end.join(" OR ")

        scope = ::PullRequestReview.where(state: [
          ::PullRequestReview.state_value(:approved),
          ::PullRequestReview.state_value(:commented),
          ::PullRequestReview.state_value(:changes_requested),
          ::PullRequestReview.state_value(:dismissed),
        ])

        scope = T.unsafe(scope).where(conditions, *pull_request_and_user_ids.flatten)

        results = scope.order("created_at desc, id desc")

        results.each_with_object({}) do |pull_request_review, reviews|
          reviews[[pull_request_review.pull_request_id, pull_request_review.user_id]] ||= pull_request_review
        end
      end
    end
  end
end
