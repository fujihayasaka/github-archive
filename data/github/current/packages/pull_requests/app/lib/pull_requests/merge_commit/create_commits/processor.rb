# typed: strict
# frozen_string_literal: true

module PullRequests
  module MergeCommit
    module CreateCommits
      class Processor
        sig do
          params(
            command: ICommand,
            request: Request,
            rebase_timeout: Integer,
            requested_at: Time,
          ).void
        end
        def initialize(command:, request:, rebase_timeout: 7, requested_at: Time.current)
          @command = command
          @request = request
          @rebase_timeout = rebase_timeout
          @requested_at = requested_at
        end

        sig { returns(Result) }
        def call
          # Using the values loaded from GitRPC and the database, determine what needs to happen to them.
          merge_commit, rebase_commit = determine_reused_commit_states

          # Determine if our commits are reusuable.
          if merge_commit.is_a?(Commits::Reused)
            if rebase_commit.is_a?(Commits::Reused) || rebase_commit.is_a?(Commits::Skipped)
              if database_mergeable_columns_correct?(merge_commit:)
                return Result.new(
                  outcome: Result::Outcome::UpToDate,
                  merge_commit:,
                  rebase_commit:
                )
              end
            end
          end

          if merge_commit.is_a?(Commits::Pending)
            merge_commit = generate_merge_commit
          end

          # Determine if we've failed to communicate with git systems and treat the commit as failed and ineligible.
          case merge_commit
          when PullRequests::GitSystems::Commit::Failed,
               PullRequests::GitSystems::Errors::Outage,
               PullRequests::GitSystems::Errors::Fatal,
               PullRequests::GitSystems::Errors::Timeout,
               PullRequests::MergeCommit::ICommand::Result::Error,
               PullRequests::MergeCommit::ICommand::Result::Timeout
            return Result.new(
              merge_commit:,
              rebase_commit: Commits::Ineligible.new,
              outcome: Result::Outcome::GitError
            )
          end

          if rebase_commit.is_a?(Commits::Skipped)
            # Don't interact with disabled rebase commits.
          elsif merge_commit.is_a?(Commits::Conflict)
            # We cannot generate a rebase commit in the scenario of a failed merge commit.
            rebase_commit = Commits::Ineligible.new
          elsif rebase_commit.is_a?(Commits::Pending)
            # We need a new rebase commit, generate it.
            rebase_commit = generate_rebase_commit(merge_commit:)
          end

          begin
            upsert_merge_commit_request_row(merge_commit:, rebase_commit:)
          rescue Errors::CommandFailed => exception
            return Result.error(exception:, merge_commit:, rebase_commit:)
          end

          begin
            enqueue_batch_ref_updates_job
          rescue Errors::CommandFailed => exception
            return Result.error(exception:, merge_commit:, rebase_commit:)
          end

          Result.new(
            outcome: Result::Outcome::Success,
            merge_commit:,
            rebase_commit:
          )
        end

        protected

        # Constant aliases to remove repetitive namespacing in the private methods below.
        Commits = Entity::Commits

        sig { returns([T.any(Commits::Reused, Commits::Pending), T.any(Commits::Reused, Commits::Pending, Commits::Skipped)]) }
        def determine_reused_commit_states
          merge_commit = @request.merge_commit
          merge_commit_tree_sha = T.let(nil, T.nilable(String))

          merge_commit = begin
            base_sha = @request.base_branch_sha
            head_sha = @request.head_branch_sha

            # Merge commits have two parent IDs that are the base_sha and head_sha used to generate the commit. We can validate
            # reuse by checking those match our current head/base state.
            if merge_commit.is_a?(Commits::Found) && merge_commit.base_sha == base_sha && merge_commit.head_sha == head_sha
              merge_commit_tree_sha = merge_commit.tree_sha
              Commits::Reused.new(sha: merge_commit.sha)
            else
              Commits::Pending.new
            end
          end

          rebase_commit = @request.rebase_commit

          if rebase_commit.is_a?(Commits::Skipped)
            return [merge_commit, rebase_commit]
          end

          rebase_commit = begin
            # Rebase commits only have one parent OID due to the history being rewritten. To validate that it is generated
            # for the same merge commit, compare the tree_oids instead.
            if rebase_commit.is_a?(Commits::Found) && rebase_commit.tree_sha == merge_commit_tree_sha
              Commits::Reused.new(sha: rebase_commit.sha)
            else
              Commits::Pending.new
            end
          end

          [merge_commit, rebase_commit]
        end

        sig { params(merge_commit: Commits::Reused).returns(T::Boolean) }
        def database_mergeable_columns_correct?(merge_commit:)
          @request.database_merge_commit_sha_value == merge_commit.sha && @request.database_mergeable_value == true
        end

        sig { returns(Result::MergeCommit) }
        def generate_merge_commit
          result = ICommand::Result.with_retry do
            @command.create_merge_commit!(
              pull_request_id: @request.pull_request_id,
              base_sha: @request.base_branch_sha,
              head_sha: @request.head_branch_sha,
            )
          end

          case result
          when GitSystems::Commit::Created
            Commits::Created.new(sha: result.sha)
          when GitSystems::Commit::Conflict
            Commits::Conflict.new(details: result.details || {})
          else
            result
          end
        end

        sig do
          params(
            merge_commit: T.any(Commits::Created, Commits::Reused)
          ).returns(Result::RebaseCommit)
        end
        def generate_rebase_commit(merge_commit:)
          result = ICommand::Result.with_retry do
            @command.create_rebase_commit!(
              pull_request_id: @request.pull_request_id,
              base_sha: @request.base_branch_sha,
              timeout: @rebase_timeout,
              merge_commit_sha: merge_commit.sha,
            )
          end

          case result
          when GitSystems::Commit::Created
            Commits::Created.new(sha: result.sha)
          when GitSystems::Commit::Conflict
            Commits::Conflict.new(details: {})
          else
            result
          end
        end

        sig do
          params(
            merge_commit: Result::MergeCommit,
            rebase_commit: Result::RebaseCommit,
          ).void
        end
        def upsert_merge_commit_request_row(merge_commit:, rebase_commit:)
          merge_sha = T.let(nil, T.nilable(String))
          merge_conflict = T.let(nil, T.nilable(T::Hash[T.untyped, T.untyped]))

          merge_state = case merge_commit
          when Commits::Created
            merge_sha = merge_commit.sha
            Enums::CommitState::Created
          when Commits::Reused
            merge_sha = merge_commit.sha
            Enums::CommitState::Reused
          when Commits::Conflict
            merge_conflict = merge_commit.details
            Enums::CommitState::Conflict
          else
            Enums::CommitState::Failed
          end

          rebase_sha = T.let(nil, T.nilable(String))
          rebase_conflict = T.let(nil, T.nilable(T::Hash[T.untyped, T.untyped]))

          rebase_state = case rebase_commit
          when Commits::Created
            rebase_sha = rebase_commit.sha
            Enums::CommitState::Created
          when Commits::Reused
            rebase_sha = rebase_commit.sha
            Enums::CommitState::Reused
          when Commits::Conflict
            rebase_conflict = rebase_commit.details
            Enums::CommitState::Conflict
          when Commits::Ineligible
            Enums::CommitState::Ineligible
          when Commits::Skipped
            Enums::CommitState::Skipped
          else
            Enums::CommitState::Failed
          end

          # TODO: Add database validations to ensure only valid states can be inserted. This should ensure
          # that the other job does not have to deal with invalid data.
          case result = ICommand::Result.with_retry do
            @command.insert_merge_commit_request!(
              pull_request_id: @request.pull_request_id,
              priority: @request.priority,
              base_repository_id: @request.base_repository_id,
              head_repository_id: @request.head_repository_id,
              base_branch_sha: @request.base_branch_sha,
              head_branch_sha: @request.head_branch_sha,
              merge_state:,
              merge_sha:,
              merge_conflict:,
              rebase_state:,
              rebase_sha:,
              rebase_conflict:,
              requested_at: @requested_at,
            )
          end
          when ICommand::Result::Error
            Failbot.report(result.exception)
            raise result.as_exception
          end
        end

        sig { void }
        def enqueue_batch_ref_updates_job
          case result = ICommand::Result.with_retry do
            @command.enqueue_batch_ref_updates_job!(pull_request_id: @request.pull_request_id)
          end
          when ICommand::Result::Error
            Failbot.report(result.exception)
            raise result.as_exception
          end
        end

        private

        sig { returns(Integer) }
        def pull_request_id
          @request.pull_request_id
        end
      end
    end
  end
end
