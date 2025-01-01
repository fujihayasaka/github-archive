# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class MergeCommitTitle < Platform::Enums::Base
      description "The possible default commit titles for merges."

      value "PR_TITLE", "Default to the pull request's title.", value: Configurable::MergeCommitTitle::PR_TITLE
      value "MERGE_MESSAGE", "Default to the classic title for a merge message (e.g., Merge pull request #123 from branch-name).", value: Configurable::MergeCommitTitle::MERGE_MESSAGE
    end
  end
end
