
# typed: strict
# frozen_string_literal: true

module PullRequests
  module MergeCommit
    module Enums
      class InvalidRequestReason < T::Enum
        enums do
          BaseBranchPushed = new("base_branch_pushed")
          ClosedOrMerged = new("closed_or_merged")
          DuplicateRequest = new("duplicate_request")
          HeadBranchPushed = new("head_branch_pushed")
          IndeterminateAndUpToDate = new("indeterminate_and_up_to_date")
          InvalidCommitState = new("invalid_commit_state")
          MergeableAndUpToDate = new("mergeable_and_up_to_date")
          MissingBaseBranchSha = new("missing_base_branch_sha")
          MissingBaseRepository = new("missing_base_repository")
          MissingCommitFromGit = new("missing_commit_from_git")
          MissingHeadBranchSha = new("missing_head_branch_sha")
          MissingHeadRepository = new("missing_head_repository")
          MissingIssue = new("missing_issue")
          MissingPullRequest = new("missing_pull_request")
          MissingRepository = new("missing_repository")
          MissingShaFromDB = new("missing_sha_from_db")
        end
      end
    end
  end
end
