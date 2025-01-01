# typed: strict
# frozen_string_literal: true

module PullRequests
  module MergeCommit
    module Enums
      class Conflict < T::Enum
        enums do
          Merge = new("merge")
          Rebase = new("rebase")
        end
      end
    end
  end
end
