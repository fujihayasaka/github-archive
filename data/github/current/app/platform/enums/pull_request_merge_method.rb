# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class PullRequestMergeMethod < Platform::Enums::Base
      description "Represents available types of methods to use when merging a pull request."

      value "MERGE", "Add all commits from the head branch to the base branch with a merge commit.", value: :merge
      value "SQUASH", "Combine all commits from the head branch into a single commit in the base branch.", value: :squash
      value "REBASE", "Add all commits from the head branch onto the base branch individually.", value: :rebase
    end
  end
end
