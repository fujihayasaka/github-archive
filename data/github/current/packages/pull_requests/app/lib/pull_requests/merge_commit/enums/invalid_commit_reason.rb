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
          SkippedMergeCommit = new("skipped_merge_commit")
        end
      end
    end
  end
end
