# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class MergeableState < Platform::Enums::Base
      description "Whether or not a PullRequest can be merged."

      value "MERGEABLE", "The pull request can be merged.", value: "mergeable"
      value "CONFLICTING", "The pull request cannot be merged due to merge conflicts.", value: "unmergeable"
      value "UNKNOWN", "The mergeability of the pull request is still being calculated.", value: "unknown"
    end
  end
end
