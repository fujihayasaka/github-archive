# typed: strict
# frozen_string_literal: true

module Elastomer
  module Interfaces
    module Document
      module MemexProjectItem
        class DraftIssueState < T::Enum
          enums do
            Open = new
          end
        end
      end
    end
  end
end
