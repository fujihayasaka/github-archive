# typed: strict
# frozen_string_literal: true

module Repositories
  class MergeCommitTitle < T::Enum
    enums do
      PR_TITLE = new
      MERGE_MESSAGE = new
    end
  end
end
