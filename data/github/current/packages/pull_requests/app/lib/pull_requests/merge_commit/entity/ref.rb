# typed: strict
# frozen_string_literal: true

module PullRequests
  module MergeCommit
    module Entity
      class Ref < T::Struct
        const :name, String
        const :commit, Entity::Commits
      end
    end
  end
end
