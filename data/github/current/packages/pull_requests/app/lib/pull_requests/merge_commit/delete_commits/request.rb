# typed: strict
# frozen_string_literal: true

module PullRequests
  module MergeCommit
    module DeleteCommits
      class Request < T::Struct
        include IRequest

        const :pull_request_id, Integer
        const :base_repository_id, Integer
        const :head_repository_id, Integer
        const :base_branch_sha, String
        const :head_branch_sha, String
      end
    end
  end
end
