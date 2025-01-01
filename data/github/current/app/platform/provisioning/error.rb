# typed: true
# frozen_string_literal: true

# Represents an error occurring during provisioning

module Platform::Provisioning
  class Error < StandardError
    ADD_MEMBER_ERROR = :add_member_error
    IDENTITY_NOT_FOUND_ERROR = :identity_not_found_error
    DUPLICATE_IDENTITY_FOUND = :duplicate_identity_found
    INTERNAL_ERROR = :internal_error
    BAD_REQUEST_ERROR = :bad_request_error
    INVALID_IDENTITY_ERROR = :invalid_identity_error
    INVITE_IDENTITY_ERROR = :invite_identity_error
    TARGET_AT_SEAT_LIMIT_ERROR = :target_at_seat_limit_error
    FORBIDDEN_ERROR = :forbidden_error
    RECONCILER_ERROR = :reconciler_error
    GROUP_NOT_FOUND_ERROR = :group_not_found_error
    INVALID_GROUP_ERROR = :invalid_group_error
    DUPLICATE_GROUP_FOUND = :duplicate_group_found
    IDENTITY_RELINK_ERROR = :identity_relink_error
    EMAIL_NOT_ASSOCIATED_WITH_LOGGED_IN_USER = :email_not_associated_with_logged_in_user
    STATEMENT_INVALID_ERROR = :statement_invalid_error

    DEFAULT_MESSAGES = {
      add_member_error: "Unable to add user as an organization member",
      target_at_seat_limit_error: "There are no available seats",
      identity_not_found_error: "Unable to find the provisioned identity",
      duplicate_identity_found: "Duplicate identity found during provisioning",
      internal_error: "An error occurred provisioning your account. Please try again",
      bad_request_error: "Misconfigured IdP, missing required attributes",
      invalid_identity_error: "The identity was invalid",
      invite_identity_error: "Error sending invitation to provisioned identity",
      forbidden_error: "The action you are trying to perform is forbidden",
      reconciler_error: "Error syncing required user account attributes",
      duplicate_group_found: "Duplicate group found during provisioning",
      group_not_found_error: "Unable to find the provisioned group",
      invalid_group_error: "The group was invalid",
      identity_relink_error: "Cannot relink identity",
      email_not_associated_with_logged_in_user: OrganizationInvitation::EMAIL_NOT_VERIFIED_ERROR_MESSAGE,
      statement_invalid_error: "Statement Invalid. Too many requests. Please try again later.",
    }

    DEFAULT_ERROR_CODES = {
      add_member_error: 403,
      target_at_seat_limit_error: 403,
      identity_not_found_error: 404,
      duplicate_identity_found: 409,
      internal_error: 500,
      bad_request_error: 400,
      invalid_identity_error: 409,
      invite_identity_error: 400,
      forbidden_error: 403,
      reconciler_error: 400,
      group_not_found_error: 404,
      invalid_group_error: 400,
      duplicate_group_found: 409,
      identity_relink_error: 403,
      email_not_associated_with_logged_in_user: 302,
      statement_invalid_error: 429, # treating it as 429
    }

    attr_reader :reason, :message

    def initialize(reason:, message: nil, error_code: nil, fatal: false)
      @reason = reason
      @message = message || default_message_for_reason(reason)
      @error_code = error_code || default_error_code_for_reason(reason)
      @fatal = fatal
      @backtrace = caller[2..-1] # default backtrace to caller of convenience constructor methods.
    end

    def to_s
      message
    end

    # Public: is current error fatal?
    #
    # Returns true or false
    def fatal?
      @fatal
    end

    # Public: error code associated with the reason
    #
    # Returns Integer
    def error_code
      @error_code || 400
    end

    # Convenience methods for quickly constructing errors of different types.
    # Each takes a `message` kwarg to override the default of the error.

    def self.add_member(message: nil, status: nil)
      # Ensure that the incoming status matches a defined status in the default messages
      # otherwise default back to add_member_error
      if status.present? && DEFAULT_MESSAGES[status].nil?
        status = ADD_MEMBER_ERROR
      end
      new(reason: status || ADD_MEMBER_ERROR, message: message)
    end

    def self.identity_not_found(message: nil)
      new(reason: IDENTITY_NOT_FOUND_ERROR, message: message)
    end

    def self.group_not_found(message: nil)
      new(reason: GROUP_NOT_FOUND_ERROR, message: message)
    end

    def self.duplicate_identity_found(message: nil)
      new(reason: DUPLICATE_IDENTITY_FOUND, message: message)
    end

    def self.duplicate_group_found(message: nil)
      new(reason: DUPLICATE_GROUP_FOUND, message: message)
    end

    def self.internal_error(message: nil)
      new(reason: INTERNAL_ERROR, message: message)
    end

    def self.bad_request_error(message: nil)
      new(reason: BAD_REQUEST_ERROR, message: message)
    end

    def self.invalid_identity(message: nil)
      new(reason: INVALID_IDENTITY_ERROR, message: message)
    end

    def self.invalid_group(message: nil)
      new(reason: INVALID_GROUP_ERROR, message: message)
    end

    def self.invite_identity(message: nil)
      new(reason: INVITE_IDENTITY_ERROR, message: message)
    end

    def self.target_at_seat_limit(message: nil)
      new(reason: TARGET_AT_SEAT_LIMIT_ERROR, message: message)
    end

    def self.forbidden_error(message: nil)
      new(reason: FORBIDDEN_ERROR, message: message)
    end

    def self.reconciler_error(message: nil, fatal: false)
      new(reason: RECONCILER_ERROR, message: message, fatal: fatal)
    end

    def self.identity_relink_error(message: nil, current_identity_identifier:, new_identity_identifier:)
      IdentityRelinkError.new \
        reason: IDENTITY_RELINK_ERROR,
        message: message,
        current_identity_identifier: current_identity_identifier,
        new_identity_identifier: new_identity_identifier
    end

    def self.statement_invalid_error(message: nil)
      new(reason: STATEMENT_INVALID_ERROR, message: message)
    end

    # Public: a Platform::Provisioning::Errors instance are the same if
    # * the error message is exactly the same
    # * the reason is exactly the same
    # ##########################
    def ==(other_error)
      eql?(other_error)
    end

    def eql?(other_error)
      @reason == other_error.reason && @message == other_error.message
    end

    def hash
      [@reason, @message].hash
    end

    # Failbot code expects things it's asked to report about to have a `backtrace` method:
    # https://github.com/github/failbot/blob/d764aed3c1d7462cbc84c6660c150608c3ab7dc4/lib/failbot.rb#L242
    def backtrace
      @backtrace
    end

    private

    def default_message_for_reason(reason)
      DEFAULT_MESSAGES.fetch(reason)
    end

    def default_error_code_for_reason(reason)
      return 400 unless DEFAULT_ERROR_CODES.include?(reason)
      DEFAULT_ERROR_CODES.fetch(reason)
    end
  end
end
