# typed: strict
# frozen_string_literal: true

module PullRequests
  module MergeCommit
    module Enums
      class CommitState < T::Enum
        enums do
          Created = new("created")
          Reused = new("reused")
          Conflict = new("conflict")
          Ineligible = new("ineligible")
          Skipped = new("skipped")
          Failed = new("failed")
        end
      end
    end
  end
end
