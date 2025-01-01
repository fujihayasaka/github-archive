# typed: strict
# frozen_string_literal: true

module PullRequests
  module ReviewComments
    module Create
      module_function

      class Success < T::Struct
        const :comment, PullRequestReviewComment
        const :thread, PullRequestReviewThread
      end

      class Error < T::Struct
        const :errors, ActiveModel::Errors
      end

      sig do
        params(
          repository: Repository,
          pull_request: PullRequest,
          author: User,
          body: String,
          diff_start_commit_oid: T.nilable(String),
          diff_end_commit_oid: T.nilable(String),
          diff_base_commit_oid: T.nilable(String),
          line: T.nilable(Integer),
          path: String,
          review: PullRequestReview,
          side: Symbol,
          start_line: T.nilable(Integer),
          start_side: Symbol,
          subject_type: Symbol,
          submit_review: T::Boolean,
        ).returns(T.any(Success, Error))
      end
      def create(
        repository:,
        pull_request:,
        author:,
        body:,
        diff_start_commit_oid:,
        diff_end_commit_oid:,
        diff_base_commit_oid:,
        line:,
        path:,
        review:,
        side:,
        start_line:,
        start_side:,
        subject_type:,
        submit_review:
      )

        orchestrator = CreateNewPullRequestReviewCommentOrchestration.create(
          repository:,
          pull_request:,
          actor: author,
          body:,
          diff_start_commit_oid:,
          diff_end_commit_oid:,
          diff_base_commit_oid:,
          line:,
          path:,
          review:,
          side:,
          start_line:,
          start_side:,
          subject_type:,
          submit_review:
        )

        orchestrator.execute

        if orchestrator.failed?
          errors = ActiveModel::Errors.new(orchestrator)
          errors.add(:base, "Failed to create comment: #{orchestrator.error_message}")
          return Error.new(errors:)
        end

        comment = orchestrator.comment
        thread = orchestrator.thread
        review = orchestrator.public_review

        if thread.errors.any?
          Error.new(errors: thread.errors)
        elsif comment.errors.any?
          Error.new(errors: comment.errors)
        elsif review.errors.any?
          Error.new(errors: review.errors)
        elsif orchestrator.error_message.present?
          errors = ActiveModel::Errors.new(orchestrator)
          errors.add(:base, "Failed to create comment: #{orchestrator.error_message}")
          Error.new(errors:)
        else
          Success.new(comment: orchestrator.comment, thread: orchestrator.thread)
        end
      end
    end
  end
end
