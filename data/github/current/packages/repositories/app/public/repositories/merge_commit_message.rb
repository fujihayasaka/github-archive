# typed: strict
# frozen_string_literal: true

module Repositories
  class MergeCommitMessage < T::Enum
    enums do
      PR_TITLE = new
      PR_BODY = new
      BLANK = new
    end
  end
end
