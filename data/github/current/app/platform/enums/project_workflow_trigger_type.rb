# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class ProjectWorkflowTriggerType < Platform::Enums::Base
      description "The trigger type that initiates the project workflow."
      visibility :internal

      value "ISSUE_CLOSED", "An issue that belongs to the project was closed.", value: ::ProjectWorkflow::ISSUE_CLOSED_TRIGGER
      value "ISSUE_PENDING_CARD_ADDED", "A project card was added from an issue.", value: ::ProjectWorkflow::ISSUE_PENDING_CARD_ADDED_TRIGGER
      value "ISSUE_REOPENED", "An issue that belongs to the project was reopened.", value: ::ProjectWorkflow::ISSUE_REOPENED_TRIGGER
      value "PR_APPROVED", "A pull request that belongs to the project was approved.", value: ::ProjectWorkflow::PR_APPROVED_TRIGGER
      value "PR_CLOSED_NOT_MERGED", "A pull request that belongs to the project was closed without merging changes.", value: ::ProjectWorkflow::PR_CLOSED_NOT_MERGED_TRIGGER
      value "PR_MERGED", "A pull request that belongs to the project was merged.", value: ::ProjectWorkflow::PR_MERGED_TRIGGER
      value "PR_PENDING_APPROVAL", "A pull request that belongs to the project has requested changes or approved reviews were dismissed.", value: ::ProjectWorkflow::PR_PENDING_APPROVAL_TRIGGER
      value "PR_PENDING_CARD_ADDED", "A project card was added from a pull request.", value: ::ProjectWorkflow::PR_PENDING_CARD_ADDED_TRIGGER
      value "PR_REOPENED", "A pull request that belongs to the project was reopened.", value: ::ProjectWorkflow::PR_REOPENED_TRIGGER
    end
  end
end
