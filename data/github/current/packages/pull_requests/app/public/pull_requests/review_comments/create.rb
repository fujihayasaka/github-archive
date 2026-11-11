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

      class BulkSuccess < T::Struct
        const :comments, T::Array[PullRequestReviewComment]
        const :threads, T::Array[PullRequestReviewThread]
      end

      class Error < T::Struct
        const :errors, ActiveModel::Errors
      end

      # Public: Create a pull request review comment using generic parameter hash.
      # This method handles comment creation using a flexible parameter format that can contain
      # any combination of valid positioning parameters (blob-based, diff-relative, or position).
      #
      # pull_request     - The PullRequest object to add the comment to.
      # actor            - The User creating the comment.
      # review           - The PullRequestReview to associate the comment with (optional).
      # review_event     - When provided, the review will be submitted with this event after adding the comment.
      #                    Valid values are :comment, :approve, :request_changes.
      #                    If nil, the review will remain in draft state.
      # body             - String content of the comment (optional).
      # parameters       - Hash-like object containing positioning and comment data in any valid format.
      # only_changed_files - Flag to determine if comments can be added to paths outside of changed files of a diff.
      # base_commit_oid  - String base commit SHA for the positioning context.
      # head_commit_oid  - String head commit SHA for the positioning context.
      #
      # Returns either a Success object containing the created comment and thread, or an Error object with validation errors.
      #
      # Raises no exceptions - returns error objects for invalid parameters or creation failures.
      sig do
        params(
          pull_request: PullRequest,
          actor: User,
          review: T.nilable(PullRequestReview),
          review_event: T.any(Symbol, String, NilClass),
          body: T.nilable(String),
          parameters: T.any(HashWithIndifferentAccess, T::Hash[T.untyped, T.untyped]),
          only_changed_files: T::Boolean,
          destination_base_commit_oid: T.nilable(String),
          destination_head_commit_oid: T.nilable(String),
        ).returns(T.any(Success, Error))
      end
      def create_from_parameters(pull_request:, actor:, review:, review_event:, body:, parameters:, only_changed_files: false, destination_base_commit_oid: nil, destination_head_commit_oid: nil)
        GitHub.dogstats.distribution_time("pull_requests.review_comments.create", tags: ["review_comments:create"]) do
          result = Service.new(
            parameters: [parameters.merge(body:)],
            pull_request:, actor:, review:, review_event:, destination_base_commit_oid:, destination_head_commit_oid:, only_changed_files:
          ).call
          case result
          when BulkSuccess
            comment = T.must(result.comments.first)
            thread = T.must(result.threads.first)
            Success.new(comment:, thread:)
          when Error
            result
          else
            T.absurd(result)
          end
        end
      end

      # Public: Create pull request review comments using a list of generic parameter hashes.
      # This method handles comment creation using a flexible parameter format that can contain
      # any combination of valid positioning parameters (blob-based, diff-relative, or position).
      #
      # pull_request     - The PullRequest object to add the comment to.
      # actor            - The User creating the comment.
      # review           - The PullRequestReview to associate the comment with (optional).
      # review_event     - When provided, the review will be submitted with this event after adding the comment.
      #                    Valid values are :comment, :approve, :request_changes.
      # parameters       - A list of Hash-like objects containing positioning and comment data in any valid format.
      # base_commit_oid  - String base commit SHA for the positioning context.
      # head_commit_oid  - String head commit SHA for the positioning context.
      #
      # Returns either a Success object containing the created comment and thread, or an Error object with validation errors.
      #
      # Raises no exceptions - returns error objects for invalid parameters or creation failures.
      sig do
        params(
          pull_request: PullRequest,
          actor: User,
          review: T.nilable(PullRequestReview),
          review_event: T.any(Symbol, String, NilClass),
          parameters: T::Array[T.any(HashWithIndifferentAccess, T::Hash[T.untyped, T.untyped])],
          only_changed_files: T::Boolean,
          destination_base_commit_oid: T.nilable(String),
          destination_head_commit_oid: T.nilable(String),
        ).returns(T.any(BulkSuccess, Error))
      end
      def create_many_from_parameters(pull_request:, actor:, review:, review_event:, parameters:, only_changed_files:, destination_base_commit_oid: nil, destination_head_commit_oid: nil)
        GitHub.dogstats.distribution_time("pull_requests.review_comments.create", tags: ["review_comments:create"]) do
          Service.new(
            pull_request:, actor:, review:, review_event:, parameters:, only_changed_files:,
            destination_base_commit_oid:, destination_head_commit_oid:,
          ).call
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
        head_commit_oid = diff_end_commit_oid || pull_request.head_sha

        if base_commit_oid.nil? || head_commit_oid.nil?
          errors.add(:base, "invalid commit range")
          return Error.new(errors:)
        end

        case attributes = PullRequests::CommentPosition::Conversion::ParamsToArguments.convert(positioning:, base_commit_oid:, head_commit_oid:)
        when PullRequests::CommentPosition::Errors
          errors.add(*attributes.to_error_tuple)
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

        GitHub.dogstats.distribution_time("pull_requests.review_comments.create", tags: ["review_comments:create"]) do
          orchestrator.execute
        end
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
