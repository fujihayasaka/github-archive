# typed: strict
# frozen_string_literal: true

module PullRequests
  module ReviewComments
    module Delete
      module_function

      class Success < T::Struct
        const :pull_request, PullRequest
      end

      class Error < T::Struct
        const :errors, ActiveModel::Errors
      end

      sig do
        params(
          repository: Repository,
          pull_request: PullRequest,
          actor: User,
          comment: PullRequestReviewComment,
        ).returns(T.any(Success, Error))
      end
      def delete(
        repository:, pull_request:, actor:, comment:
      )
        orchestrator_args = {
          repository:,
          pull_request:,
          pull_request_review_comment: comment,
          actor: actor,
          comment_user: comment.user
        }

        orchestrator = DeletePullRequestReviewCommentOrchestration.create(orchestrator_args)

        orchestrator.execute

        if orchestrator.failed? || orchestrator.skipped?
          errors = ActiveModel::Errors.new(orchestrator)
          errors.add(:base, orchestrator.error_message)
          return Error.new(errors:)
        end

        Success.new(pull_request: pull_request)
      end
    end
  end
end
