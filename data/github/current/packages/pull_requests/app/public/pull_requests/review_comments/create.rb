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
          review: PullRequestReview,
          submit_review: T::Boolean,
          positioning: T::Hash[T.untyped, T.untyped],
        ).returns(T.any(Success, Error))
      end
      def create_with_position(
        repository:,
        pull_request:,
        author:,
        body:,
        diff_start_commit_oid:,
        diff_end_commit_oid:,
        diff_base_commit_oid:,
        review:,
        submit_review:,
        positioning:
      )
        orchestrator = CreateNewPullRequestReviewCommentOrchestration.new
        errors = ActiveModel::Errors.new(orchestrator)

        base_commit_oid = diff_base_commit_oid || pull_request.merge_base
        start_commit_oid = diff_start_commit_oid || base_commit_oid
        end_commit_oid = diff_end_commit_oid || pull_request.head_sha

        if base_commit_oid.nil? || start_commit_oid.nil? || end_commit_oid.nil?
          errors.add(:base, "invalid commit range")
          return Error.new(errors:)
        end

        case attributes = PullRequests::CommentPosition::Legacy::Parameters.call(positioning:, base_commit_oid:, start_commit_oid:, end_commit_oid:)
        when PullRequests::CommentPosition::Legacy::Parameters::Errors
          errors.add(:base, attributes.serialize)
          Error.new(errors:)
        else
          create(
            repository:,
            pull_request:,
            author:,
            body:,
            review:,
            submit_review:,
            diff_base_commit_oid: attributes.diff_base_commit_id,
            diff_start_commit_oid: attributes.diff_start_commit_id,
            diff_end_commit_oid: attributes.diff_end_commit_id,
            line: attributes.line,
            start_line: attributes.start_line,
            path: attributes.path,
            side: attributes.side,
            start_side: attributes.start_side || :right,
            subject_type: attributes.subject_type,
          )
        end
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
