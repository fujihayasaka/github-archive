# typed: true
# frozen_string_literal: true

module PullRequests
  class UpdateReviewsJob < ApplicationJob
    locked_by timeout: 10.minutes, key: ->(job) {
      pull_request = job.arguments.first
      pull_request.id
    }

    queue_as :synchronize_pull_request
    retry_on_dirty_exit

    sig { params(pull_request: ::PullRequest, actor: T.nilable(::User)).void }
    def perform(pull_request, actor:)
      pull_request.promote_reviews_to_latest_head

      if pull_request.dismiss_stale_reviews?
        pull_request.dismiss_stale_reviews(
          actor: actor || User.ghost,
          changing_base: false,
          base_changed_manually: false,
        )
      end
    end
  end
end
