# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class MergeCommitMessage < Platform::Enums::Base
      description "The possible default commit messages for merges."

      value "PR_TITLE", "Default to the pull request's title.", value: Configurable::MergeCommitMessage::PR_TITLE
      value "PR_BODY", "Default to the pull request's body.", value: Configurable::MergeCommitMessage::PR_BODY
      value "BLANK", "Default to a blank commit message.", value: Configurable::MergeCommitMessage::BLANK
    end
  end
end
