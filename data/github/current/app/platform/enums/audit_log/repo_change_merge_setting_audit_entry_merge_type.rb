# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    module AuditLog
      class RepoChangeMergeSettingAuditEntryMergeType < Platform::Enums::Base
        description "The merge options available for pull requests to this repository."

        value "MERGE", "The pull request is added to the base branch in a merge commit.", value: "merge_commit"
        value "REBASE", "Commits from the pull request are added onto the base branch individually without a merge commit.", value: "rebase"
        value "SQUASH", "The pull request's commits are squashed into a single commit before they are merged to the base branch.", value: "squash"
      end
    end
  end
end
