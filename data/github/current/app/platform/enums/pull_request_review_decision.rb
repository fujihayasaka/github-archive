# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class PullRequestReviewDecision < Platform::Enums::Base
      description "The review status of a pull request."

      value "CHANGES_REQUESTED", "Changes have been requested on the pull request.",
        value: :changes_requested
      value "APPROVED", "The pull request has received an approving review.",
        value: :approved
      value "REVIEW_REQUIRED", "A review is required before the pull request can be merged.",
        value: :review_required
    end
  end
end
