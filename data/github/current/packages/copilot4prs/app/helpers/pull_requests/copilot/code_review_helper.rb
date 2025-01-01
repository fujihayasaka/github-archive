# typed: strict
# frozen_string_literal: true

module PullRequests
  module Copilot
    module CodeReviewHelper
      extend T::Helpers

      sig { params(pull_request_review_id: T.nilable(Integer), actor_id: T.nilable(Integer),).returns(T::Boolean) }
      def is_empty_copilot_review?(pull_request_review_id:, actor_id:)
        # bail if required data isn't present
        return false if actor_id.nil?
        return false if pull_request_review_id.nil?

        # combo here, checking that the app exists and that the actor_id is the reviewer bot
        copilot_pull_request_reviewer = \
          Integration.where(
            bot_id: actor_id,
            owner_id: GitHub.trusted_apps_owner_id,
            slug: Apps::Privileged::CopilotPullRequestReviewer::SLUG
          )
        return false if !copilot_pull_request_reviewer.exists?

        # Skip if the bot didn't leave any comments on this review
        review_comments = PullRequestReviewComment.where(pull_request_review_id: pull_request_review_id, user_id: actor_id)
        review_comments.empty?
      end
    end
  end
end
