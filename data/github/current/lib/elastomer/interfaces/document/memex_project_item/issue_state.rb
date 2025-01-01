# typed: strict
# frozen_string_literal: true

module Elastomer
  module Interfaces
    module Document
      module MemexProjectItem
        class IssueState < T::Enum
          extend T::Sig

          enums do
            Closed = new
            Open = new
          end
        end
      end
    end
  end
end
