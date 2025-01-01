# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    class PendingPullRequestReviewCheck < Platform::Loader
      def self.load(pull_request_id, user_id)
        self.for.load([pull_request_id, user_id])
      end

      def fetch(pull_request_and_user_ids)
        conditions = pull_request_and_user_ids.map do |_, _|
          "(`pull_request_reviews`.`pull_request_id` = ? AND `pull_request_reviews`.`user_id` = ?)"
        end.join(" OR ")

        scope = ::PullRequestReview.pending

        scope = T.unsafe(scope).where(conditions, *pull_request_and_user_ids.flatten)

        results = scope.pluck(:pull_request_id, :user_id)

        pending_review_exists = Hash.new(false)
        results.each do |pull_request_id, user_id|
          pending_review_exists[[pull_request_id, user_id]] = true
        end
        pending_review_exists
      end
    end
  end
end
