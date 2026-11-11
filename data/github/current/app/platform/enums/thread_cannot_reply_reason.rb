# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class ThreadCannotReplyReason < Platform::Enums::Base
      description "The possible errors that will prevent a user from replying to a thread."

      visibility :internal

      value "ARCHIVED", "Unable to reply to this thread because the repository is archived.", value: :archived
      value "LOCKED", "Unable to reply to this thread because the thread is locked.", value: :locked
      value "LOGIN_REQUIRED", "You must be logged in to reply to this thread.", value: :login_required
      value "VERIFIED_EMAIL_REQUIRED", "At least one email address must be verified to reply to this thread.", value: :verified_email_required

      # TODO: The `REPLY` reason should be removed by cleaning up our data model
      #       and removing the notion of "reply-reference" threads.
      value "REPLY", "Unable to reply to this thread because it's a reference to another thread.", value: :reply

      # TODO: The `MISSING_OBJECTS` reason should be removed. There is no real reason why
      #       a user should not be able to reply to a thread that is missing git objects.
      value "MISSING_OBJECTS", "Unable to reply to this thread because it's missing git objects.", value: :missing_objects
    end
  end
end
