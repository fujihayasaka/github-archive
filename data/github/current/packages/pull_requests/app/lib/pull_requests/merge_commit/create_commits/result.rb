# typed: strict
# frozen_string_literal: true

module PullRequests
  module MergeCommit
    module CreateCommits
      class Result < T::Struct
        const :merge_commit, T.any(
          Entity::Commits::Created,
          Entity::Commits::Conflict,
          Entity::Commits::Invalid,
          Entity::Commits::Reused
        )

        const :rebase_commit, T.any(
          Entity::Commits::Created,
          Entity::Commits::Conflict,
          Entity::Commits::Invalid,
          Entity::Commits::Reused, Entity::Commits::Skipped
        )
      end
    end
  end
end
