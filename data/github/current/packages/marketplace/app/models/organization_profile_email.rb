# typed: true
# frozen_string_literal: true

class OrganizationProfileEmail < ApplicationRecord::Domain::Users
  include Email::OrgEmailVerificationDependency

  ERROR_LOGGING_ENABLED = true
  ERROR_LOG_CONTEXT = :organization_profile_email_verification
  AUDIT_LOG_EVENT_PREFIX = :organization_profile_email

  validates :profile_email,
  format: {
    with: User::EMAIL_REGEX,
    message: "does not look like an email address. Enter a valid email address in your organization profile.",
  },
  allow_nil: false

  enum :state, { unverified: 0, verified: 1 }

  alias_attribute :email, :profile_email
  scope :for_profile_email, -> (profile_email) { where profile_email: profile_email }

  belongs_to :organization
  belongs_to :initiator, class_name: "User", foreign_key: :initiator_id # rubocop:todo Rails/InverseOf
  belongs_to :verifier, class_name: "User", foreign_key: :verifier_id # rubocop:todo Rails/InverseOf

  def to_s
    profile_email
  end

  # Internal: Generate token and send verification email, but only if this email
  #       has not already been verified.
  #
  # initiator - Actor requesting email verification. Passed only for reverification.
  #
  # Returns a Boolean.
  def request_verification(initiator: nil)
    opts = initiator ? { initiator: initiator } : {}
    return false unless set_verification_token!(opts: opts)

    AccountMailer.organization_email_verification(self, requested_by: self.initiator, from_profile_email_verify: true).deliver_later

    event_name = initiator ? :request_verification_resend : :request_verification
    instrument_request_verification(event_name)
    true
  end

  def verify(token, verifier)
    @from_confirm_verify = true

    opts = {
      state: :verified,
      verifier: verifier
    }
    verify_email(token, opts: opts)
  end

  # Internal: Default attributes for auditing
  def event_payload
    {
      state: state,
      note: profile_email,
      org: organization,
      actor: @from_confirm_verify ? verifier : initiator,
    }.merge(event_context)
  end

  # Internal: Payload for verification error logs
  def error_log_payload
    {
      "gh.organization.profile_email_id" => id,
      "gh.actor.login" => verifier&.login
    }
  end
end
