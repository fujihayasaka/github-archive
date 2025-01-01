# typed: strict
# frozen_string_literal: true

module PullRequests
  module MergeCommit
    module Enums
      class InvalidCommitReason < T::Enum
        enums do
          Unknown = new("unknown")
          Conflict = new("conflict")
          Timeout = new("timeout")
          AlreadyMerged = new("already_merged")
          MergeCommitConflict = new("merge_commit_conflict")
          MergeCommitInvalid = new("merge_commit_invalid")
        end
      end
    end
  end
end
