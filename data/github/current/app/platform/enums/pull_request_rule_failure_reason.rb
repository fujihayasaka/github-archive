# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class PullRequestRuleFailureReason < Platform::Enums::Base
      description "The possible violation types for the `pull_request` rule."

      required_capabilities [:mobile_only_schema_mask]

      value "CODE_OWNER_REVIEW_REQUIRED", "A review from a code owner is required", value: "code_owner_review_required"
      value "THREAD_RESOLUTION_REQUIRED", "A thread resolution is required", value: "thread_resolution_required"
      value "SOC2_APPROVAL_PROCESS_REQUIRED", "An SOC2 approval process is required", value: "soc2_approval_process_required"
      value "CHANGES_REQUESTED", "Changes have been requested", value: "changes_requested"
      value "MORE_REVIEWS_REQUIRED", "More reviews are required", value: "more_reviews_required"
      value "LAST_PUSH_APPROVAL_REQUIRED", "An approval on the last push is required", value: "last_push_approval_required"
    end
  end
end
