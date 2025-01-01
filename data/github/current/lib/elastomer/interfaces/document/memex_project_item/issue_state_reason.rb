# typed: strict
# frozen_string_literal: true

module Elastomer
  module Interfaces
    module Document
      module MemexProjectItem
        class IssueStateReason < T::Enum
          extend T::Sig

          enums do
            NotPlanned = new("not_planned")
            Reopened = new
          end
        end
      end
    end
  end
end
