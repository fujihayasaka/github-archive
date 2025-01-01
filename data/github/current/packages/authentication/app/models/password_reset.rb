# typed: true
# frozen_string_literal: true

# PasswordReset handles password reset requests from users. The `create` method
# emails a link to the user containing a SignedAuthToken[1]. Following this
# link allows the user to create a new password. This model is interacted with
# via the PasswordResetsController.
#
# [1] https://github.com/github/security-docs/blob/master/standards/Secure%20Coding%20Principles.md#remote-authentication
#
# Example usage:
#
# user  = the :mastahyeti
# reset = PasswordReset.create :email => user.email # Sends email to user
# token = reset.token
# ...
# reset = PasswordReset.find_by_token token
# reset.apply :password => "PassworD1", :password_confirmation => "PassworD1"
class PasswordReset

  TOKEN_SCOPE = "PasswordReset"
  EXPIRY      = 3.hours
  FORCED_WEAK_PASSWORD_RESET_MESSAGE = "You are accessing GitHub with a weak or compromised password. You must update your password to continue using GitHub.com."
  FORCED_2FA_WEAK_PASSWORD_RESET_MESSAGE = "You are accessing GitHub with a weak or compromised password. You must update your password after completing the two-factor challenge to continue using GitHub.com."
  INVALID_EMAIL_OR_ACCOUNT_TYPE_MESSAGE = GitHub::HTMLSafeString.make("That address is either invalid, not a <a href='#{GitHub.help_url}/account-and-profile/setting-up-and-managing-your-personal-account-on-github/managing-email-preferences/changing-your-primary-email-address'>verified primary email</a> or is not associated with a <a href='#{GitHub.help_url}/get-started/learning-about-github/types-of-github-accounts'>personal user account</a>. Organization <a href='#{GitHub.help_url}/billing/managing-your-github-billing-settings/setting-your-billing-email'>billing emails</a> are only for notifications")
  GHES_INVALID_EMAIL_MESSAGE = "The email address entered could not be matched. Please enter the email address associated with your account."
  INVALID_EMAIL_EMU_USER_MESSAGE = GitHub::HTMLSafeString.make("The email address entered either is not associated with a <a href='#{GitHub.help_url}/get-started/learning-about-github/types-of-github-accounts'>personal user account</a> or is managed by an external identity provider. Contact your enterprise administrator to reset your password.")

  attr_reader :expires

  # Find a PasswordReset by its token.
  #
  # string_token - A String SignedAuthToken.
  #
  # Returns a PasswordReset or nil.
  def self.find_by_token(string_token)  # rubocop:disable GitHub/FindByDef
    token = verify_signed_auth_token(string_token)

    if token.valid?
      new(
        user: token.user,
        email: token.data["email"],
        force: token.data["force"],
        expires: token.expires,
        two_factor_verified: token.data.fetch("two_factor_verified", false),
        two_factor_method: token.data.fetch("two_factor_method", :none),
        forced_weak_password_reset: token.data.fetch("forced_weak_password_reset", false),
      )
    end
  end

  # Create a new PasswordReset and send the reset email to the user.
  #
  # data - A hash of data for the PasswordReset
  #        :user  - A User to create the PasswordReset for (optional).
  #        :email - The email address to send the password reset to (optional).
  #
  # Returns a PasswordReset.
  def self.create(data = {})
    reset = new **data
    reset.send_email if reset.valid?
    reset
  end

  # Instantiate a new PasswordReset.
  #
  #   user:                - A User to create the PasswordReset for (optional).
  #   email:               - The email address to send the password reset to
  #                          (optional).
  #   force:               - A boolean specifying if we can send the email to an
  #                          unverified address.
  #   expires:             - When the password reset expires (default 3 hours
  #                          from now)
  #   two_factor_verified: - Has the user already verified a 2FA OTP?
  #   forced_weak_password_reset - Was this reset created by application
  #     logic e.g. weak password forced resets
  #   disallow_hard_bounce - validate that the provided email is
  #     not in a hard bounce state. Still allowed if email verification disabled or
  #     reset is initiated from a verified device. (optional).
  #   current_device_id - the id of the device initiating the reset (optional).
  #
  # Returns nothing.
  def initialize(user: nil, email: nil, force: false, expires: EXPIRY.from_now, two_factor_verified: false,
    two_factor_method: :none, forced_weak_password_reset: false, disallow_hard_bounce: false, current_device_id: nil)
    @user = user
    @requested_email = email
    @force = force
    @expires = expires
    @two_factor_verified = two_factor_verified
    @two_factor_method = two_factor_method
    @forced_weak_password_reset = forced_weak_password_reset
    @disallow_hard_bounce = disallow_hard_bounce
    @current_device_id = current_device_id
  end

  # Public: The User this PasswordReset belongs to. This will be inferred from
  # the email address if one is present.
  #
  # Returns a User or nil.
  def user
    @user ||= @requested_email ? User.find_by_email(@requested_email) : nil
  end

  # Public: The email address this PasswordReset will be sent to. This will be
  # inferred from the user if one is present.
  #
  # Returns a String email address or nil.
  def email
    # When force is true and an email address is provided, use the requested
    # email, no questions asked.
    # Used for stafftools.
    if @force && @requested_email
      @requested_email

    # If an email is requested, look for a case-insensitive match on the user's
    # stored password reset emails, then use the stored case instead of input
    # case.
    elsif @requested_email
      user.lookup_password_reset_email(@requested_email) if user

    # If no email was provided but user was, look up the user's primary email
    # address.
    # Used for stafftools.
    elsif @user
      GitHub.multi_tenant_enterprise? ? @user.outbound_email : @user.email
    else
      nil
    end
  end

  # Public: A SignedAuthToken to send in the email to the user.
  #
  # Returns a SignedAuthToken or nil if the PasswordReset is invalid.
  def token
    user.signed_auth_token(
      scope: TOKEN_SCOPE,
      expires: @expires,
      data: {
        email: email,
        force: force?,
        two_factor_verified: @two_factor_verified,
        two_factor_method: @two_factor_method,
        forced_weak_password_reset: @forced_weak_password_reset,
      },
    )
  end

  # Public: the actual password reset link the user needs to follow to reset their password.
  #
  # Returns a String
  def link
    "#{environment_friendly_link}/#{token}?auto=true"
  end

  # Returns a link to generate a _new_ password reset instance
  def new_reset_link
    if FeatureFlag.vexi.enabled?(:resend_initial_first_emu_admin_password_reset, default: false) && user.is_first_emu_owner?
      "#{environment_friendly_link}?email=#{user.remove_shortcode(email)}&slug=#{user.enterprise_managed_business.slug}"
    else
      environment_friendly_link
    end
  end

  # Update the password of the User this reset belongs to.
  #
  # password - String password.
  # password_confirmation - String password.
  #
  # Returns true if the password change is successful, false otherwise.
  def apply(password:, password_confirmation:, from_device_id: nil, parsed_useragent: nil)
    return unless valid?

    if verify_two_factor?
      # This shouldn't happen during normal use. The #edit action should have
      # rendered a 2FA prompt.
      @error_message = "Two-factor verification required"
      return false
    end

    if user.apply_password_reset(password: password, password_confirmation: password_confirmation, from_device_id: from_device_id,
      parsed_useragent: parsed_useragent, tfa: user.two_factor_authentication_enabled?, tfa_method: @two_factor_method)
      true
    else
      @error_message = user.errors.full_messages.to_sentence
      false
    end
  end

  # Public: Send a password reset token for the user to the email address.
  #
  # Returns nothing.
  def send_email
    return unless valid?
    user.forgot_password self
  end

  # Public: Do we have enough, valid information to send a password reset email?
  #
  # Returns a bool.
  def valid?
    error_message.nil?
  end

  # Public: What, if anything is missing or incorrect about the data we have?
  #
  # Returns an error String or nil.
  # rubocop:todo GitHub/BooleanMemoizationWithOrOperator
  def error_message
    @error_message ||= begin
      case error
      when :not_a_regular_user
        "That account is not a user account, you can't log in to it. Try your personal account instead."
      when :emu_user
        INVALID_EMAIL_EMU_USER_MESSAGE
      when :no_user, :blank_email, :hard_bounce
        if GitHub.single_business_environment?
          GHES_INVALID_EMAIL_MESSAGE
        else
          if error == :no_user && matches_emu_email?
            # We couldn't associate the email with a user because the user omitted the business suffix (e.g. `+fab` in
            # `monalisa+fab@ghemu.onmicrosoft.com`).  Display the more helpful EMU error message.
            INVALID_EMAIL_EMU_USER_MESSAGE
          else
            INVALID_EMAIL_OR_ACCOUNT_TYPE_MESSAGE
          end
        end
      when :unusable_email
        "The specified email address cannot be used to recover your password."
      when :unknown_email
        "The specified email address is not listed on your account."
      when :suspended
        "That account is suspended so you can't log in to it."
      end
    end
  end
  # rubocop:enable GitHub/BooleanMemoizationWithOrOperator

  def error
    return @error if defined?(@error)

    @error = begin
      if user && !user.user?
        :not_a_regular_user
      elsif !user
        :no_user
      elsif user.is_emu_and_not_first_owner?
        :emu_user
      elsif email.blank?
        :blank_email
      elsif unuseable_email? && !force?
        :unusable_email
      elsif unknown_email?
        :unknown_email
      elsif user.suspended?
        :suspended
      elsif is_email_hard_bounce?
        :hard_bounce
      end
    end
  end

  # Does the user still need to verify a 2FA OTP before resetting their
  # password?
  #
  # Returns boolean.
  def verify_two_factor?
    if user.two_factor_authentication_enabled?
      !@two_factor_verified
    else
      false
    end
  end

  # Is this 2FA OTP or recovery code valid?
  #
  # otp - The String OTP or recovery code to verify.
  #
  # Returns boolean.
  def verify_two_factor(otp, totp_type:)
    @two_factor_verified = if GitHub::TwoFactorAuthentication.recovery_code?(otp)
      user.two_factor_recover(otp)
    else
      user.valid_otp?(otp, type: totp_type, callsite: "password_reset")
    end

    @two_factor_method = GitHub::TwoFactorAuthentication.recovery_code?(otp) ? :recovery_code : totp_type if @two_factor_verified
    @two_factor_verified
  end

  # Is this U2F/webauthn challenge/response valid?
  #
  # origin        - The web origin of the client response.
  # challenge     - The U2F sign challenge from the session.
  # json_response - The JSON U2F sign response from the parameters.
  #
  # Returns boolean.
  def verify_u2f(origin, challenge, json_response)
    @two_factor_verified = !!user.webauthn_json_authenticated_registration(:password_reset, origin, challenge, json_response)
    @two_factor_method = :webauthn
  end

  # Authnd has successfully approved and verified the GitHub Mobile 2FA request
  #
  # Returns boolean.
  def verify_github_mobile_2fa
    @two_factor_verified = true
    @two_factor_method = :mobile
  end

  def forced_weak_password_reset?
    !!@forced_weak_password_reset
  end

  def weak_password_reset_message
    if verify_two_factor?
      FORCED_2FA_WEAK_PASSWORD_RESET_MESSAGE
    else
      FORCED_WEAK_PASSWORD_RESET_MESSAGE
    end
  end

  # Public: determines if this reset is using a verified email address.
  # Unverified email addresses are valid if the account doesn't have any
  # verified emails.
  #
  # Returns a boolean.
  def verified_email?
    user.emails.verified.where(email: email).exists?
  end

  # Public: determines if the device from which the reset is being requested
  # is a verified device for the email address specified in the request
  #
  # Returns a boolean.
  def verified_device?
    return @verified_device if defined?(@verified_device)

    @verified_device = false

    if @current_device_id && GitHub.sign_in_analysis_enabled?
      @verified_device = user.authenticated_devices.verified.where(device_id: @current_device_id).exists?
    end

    @verified_device
  end

  private

  # if we are in a multi-tenant enterprise _and_ on a stafftools tenant
  # we should use the password reset owners tenant to generate the link
  # otherwise we would be giving the user a link to stafftools
  def environment_friendly_link
    if GitHub.multi_tenant_enterprise? && GitHub::CurrentTenant.stafftools_tenant?
      tenant = user.enterprise_managed_business
      host_name = GitHub.host_name_with_tenant(tenant: tenant)
      url_builder = GitHub::UrlBuilder.new(host_name: host_name, scheme: GitHub.scheme)
      return "#{url_builder.url}/password_reset"
    end

    "#{GitHub.url}/password_reset"
  end

  # Private: Validate if the provided email address is in a hard bounce state
  #
  # Returns boolean.
  def is_email_hard_bounce?
    return false if force? || !@disallow_hard_bounce || !user.email_verification_applicable? || verified_device?
    user_email = UserEmail.find_by(email: email)
    user_email&.bouncing?
  end

  # Private: Should we send the reset email to a unverified email address on the
  # account?
  #
  # Returns boolean.
  def force?
    !!@force
  end

  # Private: Is the email address on the account, but not useable for password
  # resets?
  #
  # Returns a boolean.
  def unuseable_email?
    # GitHub employees must use an @github.com for password resets.
    return true if user.employee? && !email.downcase.ends_with?("@github.com")

    !user.is_password_reset_email?(email) && user.is_known_email?(email)
  end

  # Private: Is the email address not on the account?
  #
  # Returns a boolean.
  def unknown_email?
    !user.is_known_email?(email)
  end

  def self.verify_signed_auth_token(token)
    User.verify_signed_auth_token(
      token: token,
      scope: TOKEN_SCOPE,
    )
  end
  private_class_method :verify_signed_auth_token

  # Private: Does the email address deobfuscate to match one registered to a EMU?
  # Excludes first admin accounts because they are eligible for password resets.
  #
  # Returns a boolean.
  sig { returns(T::Boolean) }
  def matches_emu_email?
    return false if @user || !@requested_email

    UserEmail.where(deobfuscated_email: UserEmail.deobfuscate(@requested_email)).any? do |email|
      email.user&.is_emu_and_not_first_owner?
    end
  end
end
