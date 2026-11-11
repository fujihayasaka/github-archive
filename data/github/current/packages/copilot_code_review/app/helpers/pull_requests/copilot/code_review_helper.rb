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
          Integration.first_party.where(
            bot_id: actor_id,
            slug: Apps::Privileged::CopilotPullRequestReviewer::SLUG
          )
        # This existence check is purely a hook-routing decision (does the actor match
        # the configured Copilot PR reviewer app?), so it's safe to read from a replica.
        exists = ActiveRecord::Base.connected_to(role: :reading) { copilot_pull_request_reviewer.exists? }
        return false if !exists

        # Skip if the bot didn't leave any comments on this review
        review_comments = PullRequestReviewComment.where(pull_request_review_id: pull_request_review_id, user_id: actor_id)
        review_comments.empty?
      end
    end
  end
end
