# typed: strict
# frozen_string_literal: true

module PullRequests
  module MergeCommit
    module BatchRefUpdates
      class Request < T::Struct
        extend T::Sig

        include IRequest

        MergeCommit = T.type_alias do
          T.any(
            Entity::Commits::Created,
            Entity::Commits::Conflict,
            Entity::Commits::Invalid,
            Entity::Commits::Reused
          )
        end

        RebaseCommit = T.type_alias do
          T.any(
            Entity::Commits::Created,
            Entity::Commits::Conflict,
            Entity::Commits::Invalid,
            Entity::Commits::Reused,
            Entity::Commits::Skipped
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
      end
    end
  end
end
