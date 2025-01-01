# typed: true
# frozen_string_literal: true

# rubocop:disable GitHub/UsePlatformErrors

class Platform::Provisioning::ProvisionerStatus
  include GitHub::Authentication::UserHandler
  include Platform::Provisioning::OperationType

  INTERNAL_ERROR = "An internal error has occurred. Please try again. If the problem persists, contact support."
  IDENTITY_NOT_FOUND = "Unable to find the submitted identity. Please verify the identity information and submit again."
  IDENTITY_FOUND = "Found duplicate identity during provisioning. Please verify the identity information and submit again."
  SELF_DEPROVISION_ERROR = "Unable to deprovision the admin authenticated to perform the SCIM actions. Authenticate your SCIM client with a different account and try again."
  EMAILS_EMPTY = "External authentication provided an empty email attribute. Please have your administrator check the authentication log."
  EMAIL_TAKEN = "Another user already owns the email. Please have your administrator check the authentication log."
  LOGIN_CONFLICT = "Another user already owns the account. Please have your administrator check the authentication log."
  MISSING_LOGIN = "The response did not contain either a valid NameID or a valid configured Username attribute."
  ORGANIZATION_CONFLICT = "Cannot authenticate as an Organization"
  USER_SUSPENDED = "Your account has been suspended. Please contact your Enterprise administrator to request access."
  USER_CANNOT_BE_CREATED = "The user could not be created from the provided attributes."
  USER_CANNOT_BE_UPDATED = "The user could not be updated from the provided attributes."
  GROUP_NOT_FOUND = "Unable to find the submitted external group. Please verify the group information and submit again."
  GROUP_FOUND = "Found duplicate group during provisioning. Please verify the group information and submit again."
  MEMBER_DELETED = "Cannot add a member that has been deleted through SCIM."

  # Internal: Builds a success status for an external identity
  def self.success_identity_status(identity, audit_event: nil)
    Platform::Provisioning::Result.success(external_identity: identity, audit_event: audit_event)
  end

  # Internal: Builds a success status for a user
  def self.success_user_status(user, audit_event: nil)
    Platform::Provisioning::Result.success(user: user, audit_event: audit_event)
  end

  # Internal: Builds a success status for an external group
  def self.success_group_status(group, audit_event: nil)
    Platform::Provisioning::Result.success(external_group: group, audit_event: audit_event)
  end

  # Internal: Rollback unless a success status
  def self.rollback_unless_success(result)
    raise ActiveRecord::Rollback unless result.success?
  end

  # Internal: Builds a failed status when we weren't able to find the
  # user and/or organization to provision an identity for.
  #
  # This is not the result of user or IdP error. If this happens,
  # it is a problem on our end.
  def self.internal_error_status
    Platform::Provisioning::Result.new \
      errors: Platform::Provisioning::Error.internal_error(
        message: INTERNAL_ERROR,
      )
  end

  # Internal: Builds a failed status when the request does not have all of the
  # expected attributes
  #
  # This is a result of misconfigured IdP
  def self.bad_request_status
    Platform::Provisioning::Result.new \
      errors: Platform::Provisioning::Error.bad_request_error
  end

  # Internal: Builds a failed status when we weren't able to find the identity
  # that the user is trying to operate on
  def self.identity_not_found_error_status
    Platform::Provisioning::Result.new \
      errors: Platform::Provisioning::Error.identity_not_found(
        message: IDENTITY_NOT_FOUND,
      )
  end

  # Internal: Builds a failed status when we weren't able to find the group
  # that the user is trying to operate on
  def self.group_not_found_error_status
    Platform::Provisioning::Result.new \
      errors: Platform::Provisioning::Error.group_not_found(
        message: GROUP_NOT_FOUND,
      )
  end

  # Internal: Builds a failed status when the admin that authenticated is the
  # same as the user that they are attempting to deprovision
  def self.cannot_deprovision_self_error_status
    Platform::Provisioning::Result.new \
      errors: Platform::Provisioning::Error.forbidden_error(
        message: SELF_DEPROVISION_ERROR,
      )
  end

  # Internal: Builds a failed status when the fallback login calculated
  # from the SAML response is already mapped to a user.
  def self.login_conflict_status(message: nil)
    Platform::Provisioning::Result.new \
      errors: Platform::Provisioning::Error.invalid_identity(
        message: message ||= LOGIN_CONFLICT,
      )
  end

  # Internal: Builds a failed status when a user could not be created
  def self.create_user_status(message: nil)
    Platform::Provisioning::Result.new \
      errors: Platform::Provisioning::Error.new(
        reason: :create_user,
        message: message ||= USER_CANNOT_BE_CREATED
      )
  end

  # Internal: Builds a failed status when a user could not be updated
  def self.update_user_status(message: nil)
    Platform::Provisioning::Result.new \
      errors: Platform::Provisioning::Error.new(
        reason: :update_user,
        message: message ||= USER_CANNOT_BE_UPDATED
      )
  end

  def self.missing_login_status
    Platform::Provisioning::Result.new \
    errors: Platform::Provisioning::Error.new(
      reason: :missing_login,
      message: MISSING_LOGIN
    )
  end

  # Internal: Builds a failed status when we were able to find the identity
  # that the user is trying to operate on
  def self.duplicate_identity_found
    Platform::Provisioning::Result.new \
      errors: Platform::Provisioning::Error.duplicate_identity_found(
        message: IDENTITY_FOUND,
      )
  end

  # Internal: Builds a failed status when we were able to find the group
  # that the user is trying to operate on
  def self.duplicate_group_found
    Platform::Provisioning::Result.new \
      errors: Platform::Provisioning::Error.duplicate_group_found(
        message: GROUP_FOUND,
      )
  end

  # Internal: Builds a failed status when the user has been found, but could
  # not be automatically unsuspended.
  def self.user_suspended_status(identity)
    Platform::Provisioning::Result.new \
      external_identity: identity,
      errors: Platform::Provisioning::Error.new(
        reason: :user_suspended,
        message: USER_SUSPENDED
      )
  end

  # Internal: Builds a failed status when the emails attribute in the SAML Assertion is
  # empty
  def self.email_empty_status
    Platform::Provisioning::Result.new \
      errors: Platform::Provisioning::Error.new(
        reason: :emails_empty,
        message: EMAILS_EMPTY
      )
  end

  # Internal: Builds a failed status when the provisioning was not enabled
  def self.provisioning_not_enabled(message)
    Platform::Provisioning::Result.new \
      errors: Platform::Provisioning::Error.new(
        reason: :provisioning_not_enabled,
        message: message
      )
  end

  def self.statement_invalid_status
    Platform::Provisioning::Result.new \
      errors: Platform::Provisioning::Error.new(
        reason: :statement_invalid_error,
      )
  end
end
