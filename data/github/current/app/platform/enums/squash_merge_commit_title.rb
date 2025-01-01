# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class SquashMergeCommitTitle < Platform::Enums::Base
      description "The possible default commit titles for squash merges."

      value "PR_TITLE", "Default to the pull request's title.", value: Configurable::SquashMergeCommitTitle::PR_TITLE
      value "COMMIT_OR_PR_TITLE", "Default to the commit's title (if only one commit) or the pull request's title (when more than one commit).", value: Configurable::SquashMergeCommitTitle::COMMIT_OR_PR_TITLE
    end
  end
end
