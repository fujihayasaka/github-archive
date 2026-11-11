# typed: strict
# frozen_string_literal: true

module Repositories
  class SquashCommitMessage < T::Enum
    enums do
      COMMIT_MESSAGES = new
      PR_BODY = new
      BLANK = new
    end
  end
end
