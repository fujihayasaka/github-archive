# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class PullRequestReviewState < Platform::Enums::Base
      description "The possible states of a pull request review."

      value "PENDING", "A review that has not yet been submitted.", value: "pending"
      value "COMMENTED", "An informational review.", value: "commented"
      value "APPROVED", "A review allowing the pull request to merge.", value: "approved"
      value "CHANGES_REQUESTED", "A review blocking the pull request from merging.", value: "changes_requested"
      value "DISMISSED", "A review that has been dismissed.", value: "dismissed"
    end
  end
end
