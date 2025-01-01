# typed: strict
# frozen_string_literal: true

module PullRequests
  module MergeCommit
    module CreateCommits
      class Result < T::Struct
        class Outcome < T::Enum
          enums do
            Success = new("success")
            UpToDate = new("up_to_date")
            GitError = new("git_error")
            Error = new("error")
          end
        end

        MergeCommit = T.type_alias do
          T.any(
            Entity::Commits::Created,
            Entity::Commits::Reused,
            Entity::Commits::Conflict,
            Entity::Commits::Cacheable,
            PullRequests::GitSystems::Commit::Failed,
            PullRequests::GitSystems::Errors,
            ICommand::Result::Error,
            ICommand::Result::Timeout,
          )
        end

        RebaseCommit = T.type_alias do
          T.any(
            Entity::Commits::Created,
            Entity::Commits::Reused,
            Entity::Commits::Skipped,
            Entity::Commits::Conflict,
            Entity::Commits::Ineligible,
            PullRequests::GitSystems::Commit::Failed,
            PullRequests::GitSystems::Errors,
            ICommand::Result::Error,
            ICommand::Result::Timeout,
          )
        end

        sig do
          params(
            exception: StandardError,
            merge_commit: MergeCommit,
            rebase_commit: RebaseCommit,
          ).returns(Result)
        end
        def self.error(exception:, merge_commit:, rebase_commit:)
          new(outcome: Outcome::Error, exception:, merge_commit:, rebase_commit:)
        end

        const :outcome, Outcome
        const :merge_commit, MergeCommit
        const :rebase_commit, RebaseCommit
        const :exception, T.nilable(StandardError)
      end
    end
  end
end
