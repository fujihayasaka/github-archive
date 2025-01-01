# typed: strict
# frozen_string_literal: true

module PullRequests
  module MergeCommit
    module BatchRefUpdates
      class Request < T::Struct
        include IRequest

        MergeCommit = T.type_alias do
          T.any(
            Entity::Commits::Created,
            Entity::Commits::Reused,
            Entity::Commits::Conflict,
            Entity::Commits::Failed,
            Entity::Commits::PendingDeletion,
          )
        end

        RebaseCommit = T.type_alias do
          T.any(
            Entity::Commits::Created,
            Entity::Commits::Reused,
            Entity::Commits::Conflict,
            Entity::Commits::Ineligible,
            Entity::Commits::Failed,
            Entity::Commits::Skipped,
            Entity::Commits::PendingDeletion,
          )
        end

        const :pull_request_id, Integer
        const :database_mergeable_value, T.nilable(T::Boolean)
        const :database_merge_commit_sha_value, T.nilable(String)
        const :database_merge_conflict_record_exists, T::Boolean
        const :database_rebase_conflict_record_exists, T::Boolean

        const :merge_refname, String
        const :merge_commit, MergeCommit

        const :rebase_refname, String
        const :rebase_commit, RebaseCommit

        const :requested_at, T.nilable(Time)

        alias database_merge_conflict_record_exists? database_merge_conflict_record_exists
        alias database_rebase_conflict_record_exists? database_rebase_conflict_record_exists

        class Invalid < T::Struct
          const :reason, Enums::InvalidRequestReason
          const :merge_commit_request, MergeCommitRequest

          sig { returns(Integer) }
          def pull_request_id
            merge_commit_request.pull_request_id.to_i
          end
        end
      end
    end
  end
end
