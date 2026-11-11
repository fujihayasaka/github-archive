# typed: strict
# frozen_string_literal: true

module PullRequests
  module MergeCommit
    module CreateCommits
      class Processor
        sig do
          params(
            command: ICommand,
            requests: T::Array[Request],
            rebase_timeout: Integer,
            requested_at: Time,
          ).void
        end
        def initialize(command:, requests:, rebase_timeout: 7, requested_at: Time.current)
          @command = command
          @requests = requests
          @rebase_timeout = rebase_timeout
          @requested_at = requested_at
        end

        sig do
          params(
            command: ICommand,
            request: Request,
            rebase_timeout: Integer,
            requested_at: Time,
          ).returns(Result)
        end
        def self.call(command:, request:, rebase_timeout: 7, requested_at: Time.current)
          T.must(
            new(command:, requests: [request], rebase_timeout:, requested_at:).call.first
          )
        end

        sig { returns(Results) }
        def call
          parent_commit = T.let(nil, T.nilable(T.any(Entity::Commits::Created, Entity::Commits::Reused)))

          # Process requests sequentially, chaining each successful merge commit as the next request's parent.
          results = T.let({}, T::Hash[Request, Result])

          @requests.each do |request|
            base_sha = parent_commit&.sha || request.base_branch_sha

            results[request] = result = process(request:, base_sha:)

            case outcome = result.outcome
            when Result::Outcome::Success, Result::Outcome::UpToDate, Result::Outcome::UpdatedMergeability
              # Continue processing
            when Result::Outcome::AlreadyMerged, Result::Outcome::GitError, Result::Outcome::Error
              # Any non-successful outcome stops the chain.
              break
            else
              T.absurd(outcome)
            end

            case commit = result.merge_commit
            when Entity::Commits::Created, Entity::Commits::Reused
              # Chain forward: use this commit as the parent for the next request.
              parent_commit = commit
            when Entity::Commits::Conflict, PullRequests::GitSystems::Commit::Failed, PullRequests::GitSystems::Errors, ICommand::Result::Error, ICommand::Result::Timeout
              # Any unexpected commit type stops the chain.
              break
            else
              T.absurd(commit)
            end
          end

          # Determine the first successful result to enqueue the batch ref updates with.
          if (pull_request_id = results.find { |_, result| result.outcome == Result::Outcome::Success }&.first&.pull_request_id)
            begin
              enqueue_batch_ref_updates_job(pull_request_id:)
            rescue Errors::CommandFailed => exception
              # TODO: Nooping this error, the volume of these calls will ensure something will try again.
            end
          end

          Results.new(results.values)
        end

        protected

        sig { params(request: Request, base_sha: String).returns(Result) }
        def process(request:, base_sha:)
          # Using the values loaded from GitRPC and the database, determine what needs to happen to them.
          merge_commit, rebase_commit = determine_reused_commit_states(request:, base_sha:)

          # Determine if our commits are reusuable.
          if merge_commit.is_a?(Commits::Reused)
            if rebase_commit.is_a?(Commits::Reused) || rebase_commit.is_a?(Commits::Skipped)
              if database_mergeable_columns_correct?(request:, merge_commit:)
                return Result.new(outcome: Result::Outcome::UpToDate, merge_commit:, rebase_commit:)
              end
            end
          end

          if merge_commit.is_a?(Commits::Cacheable)
            result = @command.simulate_merge_commit_creation!(
              pull_request_id: request.pull_request_id,
              base_sha:,
              head_sha: request.head_branch_sha,
              base_repository_id: request.base_repository_id,
              head_repository_id: request.head_repository_id
            )

            case result
            when PullRequests::GitSystems::Commit::Created
              merge_commit = Commits::Reused.new(sha: merge_commit.sha)

              case rebase_commit
              when Commits::Reused, Commits::Skipped
                if database_mergeable_columns_correct?(request:, merge_commit:)
                  return Result.new(outcome: Result::Outcome::UpToDate, merge_commit:, rebase_commit:)
                end
              end
            when PullRequests::GitSystems::Commit::Conflict
              merge_commit = Commits::Pending.new
            when ICommand::Result::Error, PullRequests::GitSystems::Commit::Failed
              merge_commit = PullRequests::GitSystems::Commit::Failed.new
            else T.absurd(result)
            end
          end

          if merge_commit.is_a?(Commits::Pending)
            merge_commit = generate_merge_commit(request:, base_sha:)
          end

          # Determine if we've failed to communicate with git systems and treat the commit as failed and ineligible.
          case merge_commit
          when PullRequests::GitSystems::Commit::Failed,
               PullRequests::GitSystems::Errors::Outage,
               PullRequests::GitSystems::Errors::Fatal,
               PullRequests::GitSystems::Errors::Timeout,
               ICommand::Result::Error,
               ICommand::Result::Timeout
            return Result.new(rebase_commit: Commits::Ineligible.new, outcome: Result::Outcome::GitError, merge_commit:)
          when Commits::Created, Commits::Conflict, Commits::Reused
            # Continue, these are eligible.
          else T.absurd(merge_commit)
          end

          if rebase_commit.is_a?(Commits::Skipped)
            # Don't interact with disabled rebase commits.
          elsif merge_commit.is_a?(Commits::Conflict)
            # We cannot generate a rebase commit in the scenario of a failed merge commit.
            rebase_commit = Commits::Ineligible.new
          elsif rebase_commit.is_a?(Commits::Pending)
            # We need a new rebase commit, generate it.
            rebase_commit = generate_rebase_commit(request:, base_sha:, merge_commit:)
          end

          if merge_commit.is_a?(Commits::Reused)
            if rebase_commit.is_a?(Commits::Reused) || rebase_commit.is_a?(Commits::Skipped)
              if @command.feature_enabled?(:cprmc_inline_mergeable_update)
                case result = update_mergeable_columns(pull_request_id: request.pull_request_id, merge_commit:)
                when ICommand::Result::Success
                  return Result.new(outcome: Result::Outcome::UpdatedMergeability, merge_commit:, rebase_commit:)
                when ICommand::Result::PullRequestAlreadyMergedError
                  return Result.new(outcome: Result::Outcome::AlreadyMerged, merge_commit:, rebase_commit:)
                when ICommand::Result::Error
                  return Result.new(outcome: Result::Outcome::Error, merge_commit:, rebase_commit:)
                else T.absurd(result)
                end
              end
            end
          end

          begin
            upsert_merge_commit_request_row(request:, base_sha:, merge_commit:, rebase_commit:)
          rescue Errors::CommandFailed => exception
            return Result.error(exception:, merge_commit:, rebase_commit:)
          end

          Result.new(outcome: Result::Outcome::Success, merge_commit:, rebase_commit:)
        end

        # Constant aliases to remove repetitive namespacing in the private methods below.
        Commits = Entity::Commits

        sig { params(request: Request, base_sha: String).returns([T.any(Commits::Reused, Commits::Pending, Commits::Cacheable), T.any(Commits::Reused, Commits::Pending, Commits::Skipped)]) }
        def determine_reused_commit_states(request:, base_sha:)
          merge_commit = request.merge_commit
          merge_commit_tree_sha = T.let(nil, T.nilable(String))

          merge_commit = begin
            head_sha = request.head_branch_sha

            # Merge commits have two parent IDs that are the base_sha and head_sha used to generate the commit. We can validate
            # reuse by checking those match our current head/base state.
            if merge_commit.is_a?(Commits::Found)
              if merge_commit.base_sha == base_sha && merge_commit.head_sha == head_sha
                merge_commit_tree_sha = merge_commit.tree_sha
                Commits::Reused.new(sha: merge_commit.sha)
              elsif request.base_branch_sha != base_sha
                # When stacked on a parent PR, always regenerate the merge commit. The base of the stack uses reduced
                # merge commits, so only changes within the stack require a full rebuild.
                Commits::Pending.new
              elsif @command.determine_merge_commit_up_to_date!(pull_request_id: request.pull_request_id, base_sha:, head_sha:, merge_commit:)
                merge_commit_tree_sha = merge_commit.tree_sha
                Commits::Cacheable.new(sha: merge_commit.sha)
              else
                Commits::Pending.new
              end
            else
              Commits::Pending.new
            end
          end

          rebase_commit = request.rebase_commit

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

        sig { params(request: Request, merge_commit: T.any(Commits::Reused, Commits::Cacheable)).returns(T::Boolean) }
        def database_mergeable_columns_correct?(request:, merge_commit:)
          request.database_merge_commit_sha_value == merge_commit.sha && request.database_mergeable_value == true
        end

        sig do
          params(
            request: Request,
            base_sha: String
          ).returns(T.any(
            Entity::Commits::Created,
            Entity::Commits::Reused,
            Entity::Commits::Conflict,
            PullRequests::GitSystems::Commit::Failed,
            PullRequests::GitSystems::Errors,
            ICommand::Result::Error,
            ICommand::Result::Timeout,
          ))
        end
        def generate_merge_commit(request:, base_sha:)
          result = ICommand::Result.with_retry do
            @command.create_merge_commit!(
              pull_request_id: request.pull_request_id,
              base_sha:,
              head_sha: request.head_branch_sha,
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
            request: Request,
            base_sha: String,
            merge_commit: T.any(Commits::Created, Commits::Reused, Commits::Cacheable)
          ).returns(Result::RebaseCommit)
        end
        def generate_rebase_commit(request:, base_sha:, merge_commit:)
          result = ICommand::Result.with_retry do
            @command.create_rebase_commit!(
              pull_request_id: request.pull_request_id,
              base_sha:,
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
            request: Request,
            base_sha: String,
            merge_commit: Result::MergeCommit,
            rebase_commit: Result::RebaseCommit,
          ).void
        end
        def upsert_merge_commit_request_row(request:, base_sha:, merge_commit:, rebase_commit:)
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
              pull_request_id: request.pull_request_id,
              priority: request.priority,
              base_repository_id: request.base_repository_id,
              head_repository_id: request.head_repository_id,
              base_branch_sha: base_sha,
              head_branch_sha: request.head_branch_sha,
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

        sig { params(pull_request_id: Integer).void }
        def enqueue_batch_ref_updates_job(pull_request_id:)
          case result = ICommand::Result.with_retry do
            @command.enqueue_batch_ref_updates_job!(pull_request_id:)
          end
          when ICommand::Result::Error
            Failbot.report(result.exception)
            raise result.as_exception
          end
        end

        private

        sig { params(pull_request_id: Integer, merge_commit: Commits::Reused).returns(ICommand::MarkPullRequestAsMergeableResult) }
        def update_mergeable_columns(pull_request_id:, merge_commit:)
          result = ICommand::Result.with_retry do
            @command.mark_pull_request_as_mergeable!(pull_request_id:, merge_commit_sha: merge_commit.sha)
          end

          case result
          when ICommand::Result::Error
            Failbot.report(result.as_exception)
          end

          result
        end
      end
    end
  end
end
