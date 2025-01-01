# typed: strict
# frozen_string_literal: true

module PullRequests
  module Copilot
    # Public: Validates if an actor/user and repo/organization have access to the Copilot code review feature.
    class CodeReviewUpsellLogger
      sig { params(message: String, actor: ::User, pull: T.nilable(PullRequest), repository: T.nilable(Repository)).void }
      def self.upsell_log(message, actor:, pull: nil, repository: pull&.repository)
        return unless actor.feature_flag_enabled?(:copilot_assisted_review_upsell_logging, default: false)

        repository_id = repository&.id

        GitHub.logger.info("copilot_code_review_upsell: #{message}",
          "gh.repository.id" => repository_id,
          "gh.user.id" => actor.id,
          "gh.user.login" => actor.display_login,
          "gh.pull_request.id" => pull&.id,
        )
      end
    end
  end
end
