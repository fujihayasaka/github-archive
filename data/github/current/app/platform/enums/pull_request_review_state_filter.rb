# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class PullRequestReviewStateFilter < Platform::Enums::Base
      description "The review state by which pull requests are filtered."


      visibility :under_development

      value "APPROVED", "A review allowing the pull request to merge has been submitted.", value: "approved"
      value "CHANGES_REQUESTED", "A review blocking the pull request from merging has been submitted.", value: "changes_requested"
      value "REQUIRED", "An approving review has not yet been submitted.", value: "required"
      value "NONE", "A review has not yet been submitted.", value: "none"
    end
  end
end
