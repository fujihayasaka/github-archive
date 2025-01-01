# typed: strict
# frozen_string_literal: true

module PullRequests
  module MergeCommit
    module Enums
      class Mergeability < T::Enum
        enums do
          # `nil`
          NotDetermined = new
          # `mergeable` = true
          Mergeable = new("mergeable")
          # `mergable` = false
          Conflict = new("conflict")
          # `mergeable` = null
          Indeterminate = new("indeterminate")
        end
      end
    end
  end
end
