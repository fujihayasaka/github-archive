# typed: strict
# frozen_string_literal: true

module Elastomer
  module Interfaces
    module Document
      module MemexProjectItem
        class IssueStateReason < T::Enum
          enums do
            NotPlanned = new("not_planned")
            Duplicate = new("duplicate")
            Reopened = new
          end
        end
      end
    end
  end
end
