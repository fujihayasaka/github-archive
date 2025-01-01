# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class SquashMergeCommitMessage < Platform::Enums::Base
      description "The possible default commit messages for squash merges."

      value "PR_BODY", "Default to the pull request's body.", value: Configurable::SquashMergeCommitMessage::PR_BODY
      value "COMMIT_MESSAGES", "Default to the branch's commit messages.", value: Configurable::SquashMergeCommitMessage::COMMIT_MESSAGES
      value "BLANK", "Default to a blank commit message.", value: Configurable::SquashMergeCommitMessage::BLANK
    end
  end
end
