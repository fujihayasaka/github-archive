# typed: true
# frozen_string_literal: true

module Platform::Provisioning
  class Result
    attr_reader :external_identity, :external_group, :provisioned_user, :errors, :pending, :audit_event

    def initialize(external_identity: nil, external_group: nil, user: nil, errors: [], pending: false, audit_event: nil)
      @external_identity = external_identity
      @external_group = external_group
      @errors = Platform::Provisioning::Errors.new(errors)
      @pending = pending
      @audit_event = audit_event
      @provisioned_user = user
    end

    def self.target_at_seat_limit_error(external_identity: nil, message: nil)
      new(
        external_identity: external_identity,
        errors: Error.target_at_seat_limit(message: message),
      )
    end

    def self.success(external_identity: nil, external_group: nil, user: nil, audit_event: nil)
      new(external_identity: external_identity, external_group: external_group, user: user, audit_event: audit_event)
    end

    # Indicates that provisioning has not yet completed.
    # E.g. organization membership is being restored in the background.
    def self.pending(external_identity: nil)
      new(external_identity: external_identity, pending: true)
    end

    def success?
      errors.none?
    end

    def pending?
      errors.none? && !!pending
    end

    def internal_error?
      errors.any? { |e| e.reason == Error::INTERNAL_ERROR }
    end

    def bad_request_error?
      errors.any? { |e| e.reason == Error::BAD_REQUEST_ERROR }
    end

    def invalid_identity_error?
      errors.any? { |e| e.reason == Error::INVALID_IDENTITY_ERROR }
    end

    def add_member_error?
      errors.any? { |e| e.reason == Error::ADD_MEMBER_ERROR }
    end

    def identity_not_found_error?
      errors.any? { |e| e.reason == Error::IDENTITY_NOT_FOUND_ERROR }
    end

    def duplicate_identity_found?
      errors.any? { |e| e.reason == Error::DUPLICATE_IDENTITY_FOUND }
    end

    def group_not_found_error?
      errors.any? { |e| e.reason == Error::GROUP_NOT_FOUND_ERROR }
    end

    def invite_identity_error?
      errors.any? { |e| e.reason == Error::INVITE_IDENTITY_ERROR }
    end

    def target_at_seat_limit_error?
      errors.any? { |e| e.reason == Error::TARGET_AT_SEAT_LIMIT_ERROR }
    end

    def email_not_associated_with_logged_in_user?
      errors.any? { |e| e.reason == Error::EMAIL_NOT_ASSOCIATED_WITH_LOGGED_IN_USER }
    end

    def forbidden_error?
      errors.any? { |e| e.reason == Error::FORBIDDEN_ERROR }
    end

    def reconciler_error?
      errors.any? { |e| e.reason == Error::RECONCILER_ERROR }
    end

    def invalid_group_error?
      errors.any? { |e| e.reason == Error::INVALID_GROUP_ERROR }
    end

    def duplicate_group_found?
      errors.any? { |e| e.reason == Error::DUPLICATE_GROUP_FOUND }
    end

    def identity_relink_error?
      errors.any? { |e| e.reason == Error::IDENTITY_RELINK_ERROR }
    end

    # Public: The error messages (if any) that resulted from the validation.
    #
    # Returns an Array of Strings.
    def error_messages
      errors.map(&:message)
    end

    # Public: An HTML status error code associated with an error
    #
    # Returns Integer
    def error_code
      return nil if success?
      return 500 if errors.first.nil?

      error = case
      when invalid_identity_error? then errors.get(Error::INVALID_IDENTITY_ERROR)
      when duplicate_identity_found? then errors.get(Error::DUPLICATE_IDENTITY_FOUND)
      when invalid_group_error? then errors.get(Error::INVALID_GROUP_ERROR)
      when duplicate_group_found? then errors.get(Error::DUPLICATE_GROUP_FOUND)
      when identity_not_found_error? then errors.get(Error::IDENTITY_NOT_FOUND_ERROR)
      when target_at_seat_limit_error? then errors.get(Error::TARGET_AT_SEAT_LIMIT_ERROR)
      when add_member_error? then errors.get(Error::ADD_MEMBER_ERROR)
      when invite_identity_error? then errors.get(Error::INVITE_IDENTITY_ERROR)
      when forbidden_error? then errors.get(Error::FORBIDDEN_ERROR)
      when reconciler_error? then errors.get(Error::RECONCILER_ERROR)
      when group_not_found_error? then errors.get(Error::GROUP_NOT_FOUND_ERROR)
      when email_not_associated_with_logged_in_user? then errors.get(Error::EMAIL_NOT_ASSOCIATED_WITH_LOGGED_IN_USER)
      when internal_error? then errors.get(Error::INTERNAL_ERROR)
      when identity_relink_error? then errors.get(Error::IDENTITY_RELINK_ERROR)
      else errors.first
      end

      error.error_code
    end

    # Public: Determine the user associated with the external_identity
    #
    # Returns a User
    def user
      external_identity&.user
    end
  end
end
