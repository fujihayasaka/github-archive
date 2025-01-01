# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class PullRequestReviewEvent < Platform::Enums::Base
      description "The possible events to perform on a pull request review."

      value "COMMENT", "Submit general feedback without explicit approval.", value: "comment"
      value "APPROVE", "Submit feedback and approve merging these changes.", value: "approve"
      value "REQUEST_CHANGES", "Submit feedback that must be addressed before merging.", value: "request_changes"
      value "DISMISS", "Dismiss review so it now longer effects merging.", value: "dismiss"
    end
  end
end
