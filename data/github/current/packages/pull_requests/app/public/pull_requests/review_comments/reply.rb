# typed: strict
# frozen_string_literal: true

module PullRequests
  module ReviewComments
    module Reply
      extend T::Sig

      module_function

      class Success < T::Struct
        const :comment, PullRequestReviewComment
      end

      class Error < T::Struct
        const :errors, ActiveModel::Errors
      end

      sig do
        params(
          repository: Repository,
          pull_request: PullRequest,
          review: PullRequestReview,
          thread: PullRequestReviewThread,
          user: User,
          body: String,
          submit_review: T::Boolean,
        ).returns(T.any(Success, Error))
      end
      def create(repository:, pull_request:, review:, thread:, user:, body:, submit_review:)
        orchestrator = CreateReplyPullRequestReviewCommentOrchestration.create(
          repository:,
          pull_request:,
          review:,
          thread:,
          user:,
          body:,
          submit_review:,
        )

        orchestrator.execute!

        if orchestrator.failed?
          errors = ActiveModel::Errors.new(orchestrator)
          errors.add(:base, "Failed to create reply: #{orchestrator.error_message}")
          return Error.new(errors:)
        end

        comment = orchestrator.comment
        review = orchestrator.public_review

        if comment.errors.any?
          Error.new(errors: comment.errors)
        elsif review.errors.any?
          Error.new(errors: review.errors)
        elsif orchestrator.error_message.present?
          errors = ActiveModel::Errors.new(orchestrator)
          errors.add(:base, "Failed to create reply: #{orchestrator.error_message}")
          Error.new(errors:)
        else
          Success.new(comment: comment)
        end
      end
    end
  end
end
