# typed: strict
# frozen_string_literal: true

module Platform
  module Enums
    class ActivityType < Platform::Enums::Base
      description "The type of the activity that was performed."

      value "PUSH", "Push to the repository.", value: "push"
      value "FORCE_PUSH", "Force non-fast-forward push to the repository.", value: "force_push"
      value "BRANCH_DELETION", "Deletion of a branch in the repository.", value: "branch_deletion"
      value "BRANCH_CREATION", "Creation of a branch  in the repository.", value: "branch_creation"
      value "PR_MERGE", "Merge performed via a pull request.", value: "pr_merge"
      value "MERGE_QUEUE_MERGE", "Merge performed via the merge queue.", value: "merge_queue_merge"
    end
  end
end
