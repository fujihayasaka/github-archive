# typed: strict
# frozen_string_literal: true

module Repositories
  class SquashCommitTitle < T::Enum
    enums do
      PR_TITLE = new
      COMMIT_OR_PR_TITLE = new
    end
  end
end
