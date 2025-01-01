# typed: strict
# frozen_string_literal: true

module Elastomer
  module Interfaces
    module Document
      module MemexProjectItem
        class ContentType < T::Enum
          enums do
            DraftIssue = new("DraftIssue")
            Issue = new("Issue")
            PullRequest = new("PullRequest")
          end
        end
      end
    end
  end
end
