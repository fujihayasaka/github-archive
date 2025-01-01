# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class CommentCannotUpdateReason < Platform::Enums::Base
      description "The possible errors that will prevent a user from updating a comment."

      value "ARCHIVED", "Unable to create comment because repository is archived.", value: :archived
      value "INSUFFICIENT_ACCESS", "You must be the author or have write access to this repository to update this comment.", value: :insufficient_access
      value "LOCKED", "Unable to create comment because issue is locked.", value: :locked
      value "LOGIN_REQUIRED", "You must be logged in to update this comment.", value: :login_required
      value "MAINTENANCE", "Repository is under maintenance.", value: :maintenance
      value "VERIFIED_EMAIL_REQUIRED", "At least one email address must be verified to update this comment.", value: :verified_email_required
      value "DENIED", "You cannot update this comment", value: :denied
    end
  end
end
