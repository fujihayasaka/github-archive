# typed: strict
# frozen_string_literal: true

module PullRequests
  module MergeCommit
    module CreateCommits
      class Processor
        extend T::Sig

        sig do
          params(
            command: ICommand,
            request: Request,
            rebase_timeout: Integer,
          ).void
        end
        def initialize(command:, request:, rebase_timeout: 7)
          @command = command
          @request = request
          @rebase_timeout = rebase_timeout
        end

        sig { returns(Result) }
        def call
          # Using the values loaded from GitRPC and the database, determine what needs to happen to them.
          merge_commit = determine_merge_commit_state
          rebase_commit = determine_rebase_commit_state(merge_commit:)

          # Determine if our commits are reusuable.
          if merge_commit.is_a?(Commits::Reused)
            if rebase_commit.is_a?(Commits::Reused) || rebase_commit.is_a?(Commits::Skipped)
              if database_mergeable_columns_correct?(merge_commit:)
                return Result.new(merge_commit:, rebase_commit:)
              end
            end
          end

          if merge_commit.is_a?(Commits::Pending)
            merge_commit = generate_merge_commit
          end

          # An invalid merge commit shouldn't result in a ref update, early return and await for another request.
          if merge_commit.is_a?(Commits::Invalid)
            return Result.new(
              merge_commit:,
              rebase_commit: Commits::Invalid.merge_commit_invalid
            )
          end

          case merge_commit
          when Commits::Conflict
            # We cannot generate a rebase commit without a merge commit.
            rebase_commit = Commits::Invalid.merge_commit_conflict
          when Commits::Created
            # When a new merge_commit is created, we must always generate a new commit.
            rebase_commit = generate_rebase_commit(merge_commit:)
          when Commits::Reused
            case rebase_commit
            when Commits::Pending
              rebase_commit = generate_rebase_commit(merge_commit:)
            when Commits::Skipped, Commits::Reused
              # The existing rebase commit is valid.
            else T.absurd(rebase_commit)
            end
          else T.absurd(merge_commit)
          end

          upsert_merge_commit_request_row(merge_commit:, rebase_commit:)

          Result.new(merge_commit:, rebase_commit:)
        end

        protected

        # Constant aliases to remove repetitive namespacing in the private methods below.
        Commits = Entity::Commits
        Reasons = Enums::InvalidCommitReason
        Mergeability = Enums::Mergeability

        sig { returns(T.any(Commits::Reused, Commits::Pending)) }
        def determine_merge_commit_state
          merge = @request.merge_commit

          return merge if merge.is_a?(Commits::Pending)

          # A generated commit is always based off the tip of the target branch and the pull request's branch.
          if merge.has_parents?(@request.base_branch_sha, @request.head_branch_sha)
            Commits::Reused.new(sha: merge.sha)
          else
            Commits::Pending.new
          end
        end

        sig do
          params(
            merge_commit: T.any(Commits::Reused, Commits::Pending)
          ).returns(T.any(Commits::Reused, Commits::Pending, Commits::Skipped))
        end
        def determine_rebase_commit_state(merge_commit:)
          case rebase_commit = @request.rebase_commit
          when Commits::Skipped, Commits::Pending
            rebase_commit
          when Commits::Found
            # The merge commit must be valid for us to reuse the rebase commit as the `head` is the merge commit's SHA.
            if merge_commit.is_a?(Commits::Reused) && rebase_commit.has_parents?(@request.base_branch_sha, merge_commit.sha)
              Commits::Reused.new(sha: rebase_commit.sha)
            else
              Commits::Pending.new
            end
          else T.absurd(rebase_commit)
          end
        end

        sig { params(merge_commit: Commits::Reused).returns(T::Boolean) }
        def database_mergeable_columns_correct?(merge_commit:)
          @request.database_merge_commit_sha_value == merge_commit.sha && @request.database_mergeable_value == true
        end

        sig { returns(T.any(Commits::Created, Commits::Conflict, Commits::Invalid)) }
        def generate_merge_commit
          result = ICommand::Result.with_retry do
            @command.create_merge_commit!(
              pull_request_id: @request.pull_request_id,
              base_sha: @request.base_branch_sha,
              head_sha: @request.head_branch_sha,
            )
          end

          translate_result_to_commit(result)
        end

        sig do
          params(
            merge_commit: T.any(Commits::Created, Commits::Reused)
          ).returns(T.any(Commits::Created, Commits::Conflict, Commits::Invalid))
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

          translate_result_to_commit(result)
        end

        sig do
          params(
            merge_commit: T.any(Commits::Created, Commits::Conflict, Commits::Invalid, Commits::Reused),
            rebase_commit: T.any(Commits::Created, Commits::Conflict, Commits::Invalid, Commits::Reused, Commits::Skipped),
          ).void
        end
        def upsert_merge_commit_request_row(merge_commit:, rebase_commit:)
          merge_state = merge_commit.state_name

          case merge_commit
          when Commits::Created, Commits::Reused
            merge_sha = merge_commit.sha
            merge_conflict = nil
          when Commits::Conflict
            merge_sha = nil
            merge_conflict = merge_commit.details
          when Commits::Invalid
            merge_sha = nil
            merge_conflict = nil
          else T.absurd(merge_commit)
          end

          rebase_state = rebase_commit.state_name

          case rebase_commit
          when Commits::Created, Commits::Reused
            rebase_sha = rebase_commit.sha
            rebase_conflict = nil
          when Commits::Conflict
            rebase_sha = nil
            rebase_conflict = rebase_commit.details
          when Commits::Skipped, Commits::Invalid
            rebase_sha = nil
            rebase_conflict = nil
          else T.absurd(rebase_commit)
          end

          # TODO: Add database validations to ensure only valid states can be inserted. This should ensure
          # that the other job does not have to deal with invalid data.
          #
          # TODO: Ensure the other job parser utilizes a subset of valid commit types.
          ICommand::Result.with_retry do
            @command.insert_merge_commit_request!(
              pull_request_id: @request.pull_request_id,
              priority: @request.priority,
              base_repository_id: @request.base_repository_id,
              head_repository_id: @request.head_repository_id,
              merge_state:,
              merge_sha:,
              merge_conflict:,
              rebase_state:,
              rebase_sha:,
              rebase_conflict:,
            )
          end
        end

        private

        sig do
          params(
            result: ICommand::CreateMergeCommitResult
          ).returns(
            T.any(Commits::Created, Commits::Conflict, Commits::Invalid)
          )
        end
        def translate_result_to_commit(result)
          case result
          when GitSystems::Commit::Created
            Commits::Created.new(sha: result.sha)
          when GitSystems::Commit::Conflict
            Commits::Conflict.new(details: result.details || {})
          when GitSystems::Errors::Timeout, ICommand::Result::Timeout
            Commits::Invalid.new(reason: Reasons::Timeout)
          when GitSystems::Commit::Failed
            case result.code
            when :already_merged
              Commits::Invalid.new(reason: Reasons::AlreadyMerged)
            else
              Commits::Invalid.new(reason: Reasons::Unknown)
            end
          when GitSystems::Errors, ICommand::Result::Error
            Failbot.report(result.exception)
            Commits::Invalid.new(reason: Reasons::Unknown)
          else T.absurd(result)
          end
        end
      end
    end
  end
end
