# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class InteractionType < Platform::Enums::Base
      description "Represents the kinds of interactions a user can have with another record."
      required_capabilities [:mobile_only_schema_mask]

      value "AUTHORED", "User created the record.", value: "authored"
      value "REOPENED", "User opened the record when it was closed.", value: "reopened"
      value "COMMENTED", "User left a comment on the record.", value: "commented"
      value "RECEIVED_COMMENT", "Another user commented on the user's record.", value: "received_comment"
      value "COMMENT_EDITED", "User's comment record was edited.", value: "comment_edited"
      value "RECEIVED_COMMENT_EDITED", "Another user's comment record was edited.", value: "received_comment_edited"
      value "REVIEW_COMMENTED", "User left a comment in a pull request review.", value: "pull_request_review_commented"
      value "REVIEW_REQUESTED", "The user's review was requested on the record.", value: "review_requested"
      value "REVIEW_RECEIVED", "User's record received a review.", value: "review_received"
      value "DEPLOYED", "User deployed the record.", value: "deployed"
      value "ASSIGNED", "User was assigned to the record.", value: "assigned"
      value "REFERENCED", "The user's record was referenced via a commit.", value: "referenced"
    end
  end
end
