
# typed: strict
# frozen_string_literal: true

module PullRequests
  module MergeCommit
    module Enums
      class InvalidRequestReason < T::Enum
        enums do
          MissingPullRequest = new("missing_pull_request")
          DuplicateRequest = new("duplicate_request")
          ClosedOrMerged = new("closed_or_merged")
          MissingRepository = new("missing_repository")
          MissingBaseRepository = new("missing_base_repository")
          MissingBaseBranchSha = new("missing_base_branch_sha")
          MissingHeadRepository = new("missing_head_repository")
          MissingHeadBranchSha = new("missing_head_branch_sha")
          MergeableAndUpToDate = new("mergeable_and_up_to_date")
          IndeterminateAndUpToDate = new("indeterminate_and_up_to_date")
        end
      end
    end
  end
end
