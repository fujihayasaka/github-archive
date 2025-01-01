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
          PendingDeletion = new("delete")
        end

        sig { params(value: T.untyped).returns(T.nilable(CommitState)) }
        def self.safe_deserialize(value)
          begin
            deserialize(value)
          rescue KeyError
            nil
          end
        end
      end
    end
  end
end
