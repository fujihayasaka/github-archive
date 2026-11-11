# typed: strict
# frozen_string_literal: true

module PullRequests
  module MergeCommit
    # Interface describing all the side effects to be performed by the Processor.
    module ICommand
      extend T::Helpers
      interface!

      module Result
        extend T::Helpers
        sealed!
        abstract!

        # Call the block up until max_attempts number of times. Retrying only occurs when the Error object returned
        # permits retrying.
        sig do
          type_parameters(:T).params(
            max_attempts: Integer,
            back_off: T::Boolean,
            block: T.proc.returns(T.type_parameter(:T))
          ).returns(T.type_parameter(:T))
        end
        def self.with_retry(max_attempts = 3, back_off: false, &block)
          attempts = 0

          loop do
            attempts += 1

            case result = yield
            when ICommand::Result::Error, ICommand::Result::Timeout
              if result.permit_retry
                if attempts < max_attempts
                  next if Rails.env.test? #rubocop:disable GitHub/DoNotBranchOnRailsEnv
                  if back_off
                    delay = attempts * (2**attempts)
                    sleep(delay)
                  else
                    sleep(attempts)
                  end
                else
                  GitHub.logger.info(
                    "Retryable error",
                    "exception.message": result.as_exception,
                    "gh.merge_comment.command_retry_attempts": attempts,
                  )
                end
              end
            end

            return result
          end
        end

        class Success
          include Result
        end

        class Timeout < T::Struct
          include Result
          include PullRequests::MergeCommit::Errors

          const :exception, T.nilable(Exception)

          sig { returns(T.nilable(Exception)) }
          def as_exception
            exception || CommandFailed.new("timeout")
          end

          sig { returns(T::Boolean) }
          def permit_retry
            true
          end
        end

        class Skipped
          include Result
        end

        class PullRequestAlreadyMergedError
          include Result
        end

        # Generic "error" type return value. This is to deal with unknown/uncaught exceptions and are generally
        # only able to be reported. Concrete errors with known handling should be their own class, like CreateCommitSuccess.
        class Error < T::Struct
          include Result
          include PullRequests::MergeCommit::Errors

          const :message, String
          const :permit_retry, T::Boolean, default: false
          const :exception, T.nilable(Exception), default: nil

          sig { returns(CommandFailed) }
          def as_exception
            domain_exception = CommandFailed.new(message)

            if exception.nil?
              domain_exception
            else
              wrap_exception_with(domain_exception)
            end
          end

          private

          sig { params(wrapper: CommandFailed).returns(CommandFailed) }
          def wrap_exception_with(wrapper)
            # The only way to set the `cause` field on an exception is to raise
            # it from a rescue block. In this case, we want to set our exception
            # as the cause of a `MergeQueues::CommandFailed` instance.
            begin
              raise T.must(exception)
            rescue
              raise wrapper
            end
          rescue CommandFailed => result
            result
          end
        end
      end

      GenericResult = T.type_alias { T.any(Result::Success, Result::Error) }

      TransitionToProcessingResult = T.type_alias { T.any(Result::Success, Result::Error) }
      sig { abstract.params(pull_request_ids: T::Array[Integer]).returns(TransitionToProcessingResult) }
      def transition_to_processing!(pull_request_ids:); end

      CreateMergeCommitResult = T.type_alias do
        T.any(
          PullRequests::GitSystems::Commit::Created,
          PullRequests::GitSystems::Commit::Conflict,
          PullRequests::GitSystems::Commit::Failed,
          PullRequests::GitSystems::Errors,
          ICommand::Result::Error,
          ICommand::Result::Timeout
        )
      end
      sig do
        abstract.params(
          pull_request_id: Integer,
          head_sha: String,
          base_sha: String,
          merge_base: T.nilable(String),
          commit_message: T.nilable(String),
          author_email: T.nilable(String),
        ).returns(CreateMergeCommitResult)
      end
      def create_merge_commit!(pull_request_id:, head_sha:, base_sha:, merge_base: nil, commit_message: nil, author_email: nil); end

      CreateRebaseCommitResult = T.type_alias { CreateMergeCommitResult }
      sig { abstract.params(pull_request_id: Integer, base_sha: String, merge_commit_sha: String, timeout: Integer).returns(CreateRebaseCommitResult) }
      def create_rebase_commit!(pull_request_id:, base_sha:, merge_commit_sha:, timeout:); end

      class RefUpdate < T::Struct
        const :pull_request_id, Integer
        const :name, String
        const :sha, String
      end

      UpdateRefsResult = T.type_alias { T.any(Result::Success, Result::Error) }
      sig { abstract.params(updates: T::Array[RefUpdate]).returns(UpdateRefsResult) }
      def update_refs!(updates:); end

      MarkPullRequestAsMergeableResult = T.type_alias { T.any(Result::Success, Result::Error, Result::PullRequestAlreadyMergedError) }
      sig { abstract.params(pull_request_id: Integer, merge_commit_sha: String).returns(MarkPullRequestAsMergeableResult) }
      def mark_pull_request_as_mergeable!(pull_request_id:, merge_commit_sha:); end

      MarkPullRequestAsUnmergeableResult = T.type_alias { T.any(Result::Success, Result::Error, Result::PullRequestAlreadyMergedError) }
      sig { abstract.params(pull_request_id: Integer).returns(MarkPullRequestAsUnmergeableResult) }
      def mark_pull_request_as_unmergeable!(pull_request_id:); end

      sig { abstract.params(pull_request_id: Integer, details: T::Hash[T.untyped, T.untyped], type: Enums::Conflict).returns(GenericResult) }
      def store_conflicts!(pull_request_id:, details:, type:); end

      sig { abstract.params(pull_request_id: Integer, type: Enums::Conflict).returns(GenericResult) }
      def clear_conflicts!(pull_request_id:, type:); end

      ClearMergeabilityResult = T.type_alias { T.any(Result::Success, Result::Error) }
      sig { abstract.params(pull_request_id: Integer).returns(ClearMergeabilityResult) }
      def clear_mergeability!(pull_request_id:); end

      DeleteProcessingRequestsResult = T.type_alias { T.any(Result::Success, Result::Error) }
      sig { abstract.params(pull_request_ids: T::Array[Integer]).returns(DeleteProcessingRequestsResult) }
      def delete_processing_requests!(pull_request_ids:); end

      DispatchMergabilityResult = T.type_alias { T.any(Result::Success, Result::Error) }
      sig { abstract.params(pull_request_id: Integer).returns(DispatchMergabilityResult) }
      def dispatch_mergeability_event!(pull_request_id:); end

      MergeState = T.type_alias do
        T.any(
          Enums::CommitState::Created,
          Enums::CommitState::Reused,
          Enums::CommitState::Conflict,
          Enums::CommitState::Failed,
          Enums::CommitState::PendingDeletion,
        )
      end

      RebaseState = T.type_alias { Enums::CommitState }

      InsertMergeCommitRequestResult = T.type_alias { T.any(Result::Success, Result::Error) }
      sig do
        abstract.params(
          pull_request_id: Integer,
          priority: Enums::Priority,
          base_repository_id: Integer,
          head_repository_id: Integer,
          base_branch_sha: String,
          head_branch_sha: String,
          merge_sha: T.nilable(String),
          merge_state: MergeState,
          merge_conflict: T.nilable(T::Hash[T.untyped, T.untyped]),
          rebase_sha: T.nilable(String),
          rebase_state: RebaseState,
          rebase_conflict: T.nilable(T::Hash[T.untyped, T.untyped]),
          requested_at: Time,
        ).returns(InsertMergeCommitRequestResult)
      end
      def insert_merge_commit_request!(
        pull_request_id:,
        priority:,
        base_repository_id:,
        head_repository_id:,
        base_branch_sha:,
        head_branch_sha:,
        merge_sha:,
        merge_state:,
        merge_conflict:,
        rebase_sha:,
        rebase_state:,
        rebase_conflict:,
        requested_at:
      )
      end

      # This only takes a pull_request_id because it's currently needed for the Logging class.
      EnqueueBatchRefUpdatesJobResult = T.type_alias { T.any(Result::Success, Result::Error) }
      sig { abstract.params(pull_request_id: Integer).returns(EnqueueBatchRefUpdatesJobResult) }
      def enqueue_batch_ref_updates_job!(pull_request_id:); end

      sig { abstract.params(name: Symbol).returns(T::Boolean) }
      def feature_enabled?(name); end

      SimulateMergeCommitCreationResult = T.type_alias do
        T.any(
          PullRequests::GitSystems::Commit::Created,
          PullRequests::GitSystems::Commit::Conflict,
          PullRequests::GitSystems::Commit::Failed,
          ICommand::Result::Error,
        )
      end
      sig do
        abstract.params(
          pull_request_id: Integer,
          base_sha: String,
          head_sha: String,
          base_repository_id: Integer,
          head_repository_id: Integer
        ).returns(SimulateMergeCommitCreationResult)
      end
      def simulate_merge_commit_creation!(pull_request_id:, base_sha:, head_sha:, base_repository_id:, head_repository_id:); end

      sig do
        abstract.params(
          pull_request_id: Integer,
          base_sha: T.nilable(String),
          head_sha: T.nilable(String),
          use_current_base_sha: T::Boolean
        ).returns(T.nilable(String))
      end
      def find_best_merge_base_sha!(pull_request_id:, base_sha: nil, head_sha: nil, use_current_base_sha: false); end

      sig do
        abstract.params(
          pull_request_id: Integer,
          base_sha: T.nilable(String),
          head_sha: T.nilable(String),
          merge_commit: CreateCommits::Request::MergeCommit,
        ).returns(T::Boolean)
      end
      def determine_merge_commit_up_to_date!(pull_request_id:, base_sha:, head_sha:, merge_commit:); end
    end
  end
end
