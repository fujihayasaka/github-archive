# typed: true
# frozen_string_literal: true

module Email::OrgEmailVerificationDependency
  include Instrumentation::Model
  extend T::Helpers

  requires_ancestor { OrganizationProfileEmail }

  VERIFICATION_ERROR_PREFIX = "There was an error verifying your email"
  ERRORS = {
    already_verified: "%{email} is already verified.",
    missing_token: "#{VERIFICATION_ERROR_PREFIX}. Please try re-verifying it.",
    incorrect_token: "#{VERIFICATION_ERROR_PREFIX} due to incorrect token. Please try from the latest verification email received.",
    blank_token: "#{VERIFICATION_ERROR_PREFIX} due to blank token. Please try to resend a new verification email."
  }

  # Internal: Generate token only if this email has not already been verified.
  #
  # opts -  Hash of additional columns to update
  #       Example usage:
  #       opts = {initiator: initiator}
  #       set_verification_token!(opts)
  #
  # Returns a Boolean.
  def set_verification_token!(opts: {})
    return false if !valid? || verified?

    self.verification_token = SecureRandom.hex(20)
    if opts.present?
      update_additional_attributes(opts)
    end
    save!
  end

  # Internal: Mark email as verified if there are no errors
  #
  # opts -  Hash of additional columns to update
  #       Example usage:
  #       opts = {state: :verified, verifier: verifier}
  #       verify(token, opts)
  #
  # Returns verification status along with appropriate error message.
  def verify_email(token, opts: {})
    return verification_result(false, :already_verified) if verified?
    return verification_result(false, :blank_token) if token.blank?
    return verification_result(false, :missing_token) if verification_token.blank?

    if confirm_verification(token, opts)
      verification_result(true, nil)
    else
      verification_result(false, :incorrect_token)
    end
  end

  # Internal: Check token and verify the email if it matches.
  #
  # token - A String token value to compare to the verification token for this email.
  # opts - Hash of additional columns to update
  #
  # Returns a Boolean indicating if the verification succeeded.
  def confirm_verification(token, opts)
    return false unless SecurityUtils.secure_compare(verification_token, token)

    clear_verification_token
    verify!(opts)
    instrument_confirm_verification
    true
  end

  # Internal: Clear the verification_token
  def clear_verification_token
    self.verification_token = nil
  end

  # Internal: Sets this email as verified
  #
  # Returns nothing.
  def verify!(opts)
    self.verified_at = Time.current
    if opts.present?
      update_additional_attributes(opts)
    end
    save!
  end

  # Internal: Creates verification repsonse with correct status
  #       and logs verification errors if logging is enabled
  #
  # success - Status of verification (true/ false
  # error - Error code in case of verification failure
  #
  # Returns verification status along with appropriate error message.
  def verification_result(is_successful, error)
    if is_successful
      VerifyResult.new(is_successful, nil, nil)
    else
      if error != :already_verified
        error_payload = {
        "exception.type" => OrganizationProfileEmail::ERROR_LOG_CONTEXT,
        "exception.message" => error.to_s,
        }.merge(error_log_payload)
        GitHub.logger.warn("Email verification failed", error_payload)
      end
      VerifyResult.new(is_successful, error, ERRORS[error] % { email: "#{email}" })
    end
  end

  # Internal: Prefix for auditing / instrumentation
  def event_prefix
    OrganizationProfileEmail::AUDIT_LOG_EVENT_PREFIX
  end

  # Internal: Context for audit logging
  def event_context(prefix: OrganizationProfileEmail::AUDIT_LOG_EVENT_PREFIX)
    {
      prefix => email,
      "#{prefix}_id".to_sym => id,
    }
  end

  private

  def update_additional_attributes(opts)
    update(opts)
  end

  # Internal: Instrument the email verification request.
  #
  # Returns nothing.
  def instrument_request_verification(event_name)
    instrument event_name
  end

  # Internal: Instrument the email verification confirmation.
  #
  # Returns nothing.
  def instrument_confirm_verification
    instrument :confirm_verification, verified_at: verified_at
  end

  class VerifyResult
    attr_reader :success, :error, :error_message

    def initialize(success, error, error_message)
      @success = success
      @error = error
      @error_message = error_message
    end
  end
end
