# typed: strict
# frozen_string_literal: true

module Elastomer
  module Interfaces
    module Document
      module MemexProjectItem
        class PullRequestState < T::Enum
          enums do
            Closed = new
            Merged = new
            Open = new
          end
        end
      end
    end
  end
end
