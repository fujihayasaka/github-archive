# typed: true
# frozen_string_literal: true

class UserEmail::Verify

  # Public: Attempts to verify an email.
  #
  # inputs - Hash containing attributes for verifying an email.
  # inputs[:email_id] - The Integer database ID of the UserEmail you want to verify.
  # inputs[:token] - The String verification token that you're using to verify this email.
  # inputs[:owner] - The User who owns the email that is being verified.
  #
  # Returns a UserEmail::Verify::Result.
  def self.call(inputs)
    new(**inputs).call
  end

  def initialize(email_id:, token:, owner:)
    @email_id = email_id
    @token    = token
    @owner    = owner
  end

  def call
    return Result.failure(error: :not_found) if email.blank?

    if AuthenticationLimit.at_any?(email_verification_login: owner.login, increment: true)
      return Result.failure(error: :rate_limited, email: email)
    end

    return Result.failure(error: :enterprise_managed, email: email) if owner.is_emu_and_not_first_owner?
    return Result.failure(error: :already_verified, email: email) if email.verified?
    return Result.failure(error: :missing_token, email: email) if email.verification_token.blank?
    return Result.failure(error: :verification_failed, email: email) if token.blank?

    if email.launch_code_expired?
      email.request_verification
      return Result.failure(error: :launch_code_expired, email: email)
    end

    if email.confirm_verification(token)
      Result.success(email: email)
    else
      Result.failure(error: :verification_failed, email: email)
    end
  end

  private

  attr_reader :email_id, :token, :owner

  def email
    return @email if defined?(@email)
    return @email = nil if email_id.blank? || owner.blank?
    @email = UserEmail.find_email_for_verification(email_id, owned_by: owner)
  end

  class Result
    VALID_ERRORS = [
      :rate_limited,
      :not_found,
      :enterprise_managed,
      :already_verified,
      :missing_token,
      :verification_failed,
      :launch_code_expired,
    ]

    attr_reader :success, :email, :error, :error_message
    alias_method :success?, :success

    def initialize(success:, email:, error:)
      @success       = success
      @email         = email
      @error         = error
      @error_message = message_for(email: email, error: error)
    end

    def self.success(email:)
      new(success: true, email: email, error: nil)
    end

    def self.failure(error:, email: nil)
      new(success: false, error: error, email: email)
    end

    private

    def message_for(email: nil, error:)
      return if error.blank?

      unless VALID_ERRORS.include?(error)
        raise ArgumentError, "`error` was expected to be one of `VALID_ERRORS`, but was #{error}"
      end

      case error
      when :rate_limited
        "Too many attempts. Try again later."
      when :not_found
        "Sorry, we couldn’t find an email to verify."
      when :enterprise_managed
        UserEmail::ENTERPRISE_MANAGED_USER_ERROR
      when :already_verified
        "#{email} is already verified."
      when :missing_token
        "There was an error verifying your email. Please try re-verifying it."
      when :verification_failed
        if email.launch_code_verification?
          "Invalid launch code."
        else
          "There was an error verifying your email."
        end
      when :launch_code_expired
        "This launch code has expired. We've sent a new code to #{@email}."
      end
    end
  end
end
