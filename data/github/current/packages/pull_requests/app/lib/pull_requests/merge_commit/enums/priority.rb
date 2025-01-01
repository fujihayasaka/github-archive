# typed: strict
# frozen_string_literal: true

module PullRequests
  module MergeCommit
    module Enums
      class Priority < T::Enum
        enums do
          High = new(0)
          Medium = new(1)
          Low = new(2)
        end
      end
    end
  end
end
