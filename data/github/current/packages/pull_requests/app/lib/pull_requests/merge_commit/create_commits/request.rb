# typed: strict
# frozen_string_literal: true

module PullRequests
  module MergeCommit
    module CreateCommits
      class Request < T::Struct
        extend T::Sig

        include IRequest

        MergeCommit = T.type_alias do
          T.any(Entity::Commits::Found, Entity::Commits::Pending)
        end

        RebaseCommit = T.type_alias do
          T.any(Entity::Commits::Found, Entity::Commits::Pending, Entity::Commits::Skipped)
        end

        const :priority, Enums::Priority

        const :pull_request_id, Integer
        const :base_repository_id, Integer
        const :head_repository_id, Integer

        const :base_branch_sha, String
        const :head_branch_sha, String

        const :rebase_commit, RebaseCommit
        const :merge_commit, MergeCommit

        const :database_merge_conflict_record_exists, T::Boolean
        const :database_mergeable_value, T.nilable(T::Boolean)
        const :database_merge_commit_sha_value, T.nilable(String)

        alias database_merge_conflict_record_exists? database_merge_conflict_record_exists
      end
    end
  end
end
