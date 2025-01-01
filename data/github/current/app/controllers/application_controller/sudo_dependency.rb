# typed: true
# frozen_string_literal: true

# Sudo filter protects actions by rendering an interstitial when sudo challenge
# has not been authenticated in some period of time.
# * GET requests render the sudo form that POSTs to /sessions/sudo and
#   redirects to params[:sudo_return_to] with the original GET params
# * POST requests render the sudo form but POST to the original URL,
#  preserving the params and adding them to the body.
module ApplicationController::SudoDependency
  extend ActiveSupport::Concern
  extend AbstractController::Helpers::ClassMethods
  include ApplicationController::GitHubMobileAuthDependency
  extend T::Helpers

  include WebauthnHelper::ControllerMethods
  requires_ancestor { ApplicationController }

  # For GET requests which enable sudo, we preserve the sudo status in the `_gh_sess` cookie,
  # via flash, to avoid writes to the database. This allows us to propagate the sudo
  # status to a proceeding write action where it can be persisted to the `user_sessions` table.
  # Since it gets discarded after the first request/redirect, we only need a short expiration.
  RECENT_SUDO_EXPIRY = 1.minute

  included do
    helper_method :valid_sudo_session?
  end

  def enable_sudo
    set_sudo_authenticated_at(store: flash.now)
    user_session.enable_sudo
  end

  private

  def sudo_filter
    perform_sudo_filter
  end

  # Request and check sudo access. If the sudo session is valid, it is
  # renewed without a password prompt. If the session is not valid, the sudo
  # prompt will be rendered.
  #
  # store: either flash.now (default, POST requests) or flash (GET requests,
  #   passed in by sudo/sudo action)
  #
  # returns true if the sudo session is valid. Renders a sudo prompt and
  # halts the filter chain if the session is not valid.
  def perform_sudo_filter(store: flash.now)
    return true unless GitHub.auth.sudo_mode_enabled?(current_user)
    return redirect_to_login unless logged_in?

    active_credential_option = submitted_credential_option
    authenticate_sudo_credentials!(store, active_credential_option)

    if valid_sudo_session? || recently_solved_sudo_challenge?(store)
      user_session.enable_sudo

      current_user.set_low_two_factor_method_banner(:sudo) if !request.get? && current_user.show_low_two_factor_method_banner?

      if active_credential_option == "sms" || active_credential_option == "app"
        current_user.clear_two_factor_checkup_date
      end

      true
    else
      if request.xhr?
        if @at_auth_limit
          head :too_many_requests
        else
          head :unauthorized
        end
      else
        flash.now[:error] = "Too many attempts." if @at_auth_limit
        active_credential_option = "password" if first_sudo_for_2fa_checkup(active_credential_option)
        GitHub.dogstats.increment("sudo_filter.challenge", tags: ["controller:#{params[:controller]}", "action:#{params[:action]}", "credential_type:#{active_credential_option}"])
        @hide_security_warning = true
        render "sudo/sudo", layout: "layouts/session_authentication", locals: { active_credential_option: active_credential_option }
      end
    end
  end

  # Because GET-based/AJAX sudo filters involve POSTing to /sessions/sudo
  # before redirecting to the desired endpoint, we perform the sudo
  # challenge using flash instead of flash.now.
  def get_based_sudo_filter
    perform_sudo_filter(store: flash)
  end

  # Internal: determine whether or not a sudo session is valid for the
  # current user session.
  def valid_sudo_session?
    return true unless GitHub.auth.sudo_mode_enabled?(current_user)
    user_session&.sudo?
  end

  # Internal: Validate sudo_login/sudo_password params and enable sudo mode.
  #
  # Returns the timestamp of the recent sudo challenge success or nil if
  # invalid (or no) credentials are supplied in this request.
  def authenticate_sudo_credentials!(store, active_credential_option)
    valid_credentials = false

    if active_credential_option == "webauthn"
      valid_credentials = valid_sudo_u2f?(params[:sudo_return_to])
    elsif active_credential_option == "password"
      valid_credentials = valid_sudo_password?
    elsif active_credential_option == "app" || active_credential_option == "sms"
      valid_credentials = valid_sudo_otp?
    end

    if valid_credentials
      set_sudo_authenticated_at(store)
    end
  end

  # Used to persist which credential option was used to authenticate
  # This is used on the interstitial sudo prompt only.
  # The modal handles errors via ajax and DOM manipulation, so it doesn't need to persist this.
  def submitted_credential_option
    return "webauthn" if params[:webauthn_response].present?
    return "password" if params[:sudo_password].present?
    return "app" if params[:sudo_app_otp].present?
    return "sms" if params[:sudo_sms_otp].present?

    params[:credential_type]
  end

  # Internal: store the last successful sudo challenge timestamp in
  # flash (GETs) or flash.now (POSTs).
  #
  # Returns the current timestamp
  def set_sudo_authenticated_at(store)
    store[sudo_authenticated_at_key] = Time.now.to_s
  end

  def sudo_authenticated_at_key
    "sudo_authenticated_at:#{current_user.id}"
  end

  # Internal: has a user entered their password successfully during a sudo
  # challenge recently?
  #
  # Pull the timestamp of the last successful sudo challenge response from
  # the previous request (by using flash), return true if this value is
  # within the valid window for the access level.
  def recently_solved_sudo_challenge?(store)
    return false unless authed_at = store[sudo_authenticated_at_key] # checks flash and flash.now

    DateTime.parse(authed_at) > RECENT_SUDO_EXPIRY.ago
  end

  # Internal: is this the first sudo attempt when reconfiguring 2fa due to the 1 month checkup
  def first_sudo_for_2fa_checkup(active_credential_option)
    !active_credential_option &&
    request.path == "/settings/two_factor_authentication/setup/intro" &&
    current_user.is_due_for_two_factor_checkup?
  end

  # Internal: Did the user successfully authenticate with her password?
  #
  # Returns boolean.
  def valid_sudo_password?
    return false unless params[:sudo_password]

    sudo_login    = params.delete :sudo_login
    sudo_password = params.delete :sudo_password

    # Enterprise + external auth require both the login & password to
    # confirm a user because we may cleanup a login that is valid in LDAP,
    # for example. In that case we use the POSTed login parameter instead
    # of the current user's login.
    if !GitHub.auth.external_user?(current_user)
      sudo_login = current_user.login # rubocop:disable GitHub/DoNotAllowLogin login is expected in logs
    end

    auth_result = GitHub.auth.sudo_password_authenticate(
      sudo_login, sudo_password
    )

    session[::CompromisedPassword::WEAK_PASSWORD_KEY] = auth_result.has_compromised_password.present?

    if auth_result.at_auth_limit_failure?
      @at_auth_limit = true
      instrument_sudo_prompt(success: false, credential_type: "password", result: "exceeded_attempts")
      false
    elsif auth_result.failure?
      flash.now[:error] = "Incorrect password."
      instrument_sudo_prompt(success: false, credential_type: "password", result: "auth_failure")
      false
    elsif auth_result.user != current_user
      flash.now[:error] = "Incorrect username."
      instrument_sudo_prompt(success: false, credential_type: "password", result: "user_mismatch")
      false
    else
      instrument_sudo_prompt(success: true, credential_type: "password", result: "success")
      true
    end
  end

  # Internal: Did the user successfully authenticate with U2F?
  #
  # Returns boolean.
  def valid_sudo_u2f?(sudo_return_to)
    if @at_auth_limit = AuthenticationLimit.at_any?(two_factor_login: current_user.login) # rubocop:disable GitHub/DoNotAllowLogin login used internally to lookup user see AuthenticationLimit#instrument_lockout
      instrument_sudo_prompt(success: false, credential_type: "webauthn", result: "exceeded_attempts")
      return false
    end

    sign_response_json = params[:webauthn_response]
    challenge, _ = webauthn_sign_challenge_from_request(current_user)
    return false if [sign_response_json, challenge].any?(&:blank?)

    origin = Addressable::URI.new(scheme: request.scheme, host: request.host).to_s
    authenticated_registration = current_user.webauthn_json_authenticated_registration(:two_factor_sudo, origin, challenge, sign_response_json)
    success = !!authenticated_registration
    @at_auth_limit = true if AuthenticationLimit.at_any?(two_factor_login: current_user.login, increment: !success, actor_ip: request.remote_ip) # rubocop:disable GitHub/DoNotAllowLogin login used internally to lookup user see AuthenticationLimit#instrument_lockout

    if success
      associate_trusted_device_with_client(authenticated_registration, :webauthn_authenticate_sudo)
      flag_security_key_upgrade(sudo_return_to, sign_response_json)
    end

    flash.now[:error] = "Sudo authentication failed." if !success
    instrument_sudo_prompt(success: success, credential_type: "webauthn", result: success ? "success" : "auth_failure")
    success
  end

  def flag_security_key_upgrade(sudo_return_to, sign_response_json)
    sign_response_hash = JSON.parse(sign_response_json)
    security_key = current_user.u2f_registrations.security_keys.find_by_key_handle(sign_response_hash["rawId"])
    valid_scenario = sudo_return_to && (sudo_return_to.end_with?(trusted_device_registration_prompt_path) || sudo_return_to.include?("#{trusted_device_registration_prompt_path}?"))
    session[:security_key_to_upgrade] = security_key.id if security_key&.is_passkey_eligible_on_auth?(:sudo, current_device_id, sudo_eligible = valid_scenario)
  end

  # Internal: Did the user successfully authenticate with a OTP?
  #
  # Returns boolean.
  def valid_sudo_otp?
    credential_type = ""
    received_otp = ""
    if params[:sudo_app_otp]
      credential_type = :app
      received_otp = params[:sudo_app_otp]
    elsif params[:sudo_sms_otp]
      credential_type = :sms
      received_otp = params[:sudo_sms_otp]
    end
    return false unless received_otp
    # strip the otp from the params.. we don't need it again after this
    params.delete :sudo_app_otp
    params.delete :sudo_sms_otp

    if @at_auth_limit = AuthenticationLimit.at_any?(two_factor_login: current_user.login) # rubocop:disable GitHub/DoNotAllowLogin login used internally to lookup user see AuthenticationLimit#instrument_lockout
      instrument_sudo_prompt(success: false, credential_type: credential_type, result: "exceeded_attempts")
      return false
    end
    otp = TwoFactorCredential.normalize_otp(received_otp)

    # if this looks like a recovery code, let the user know that they can't use it here
    if GitHub::TwoFactorAuthentication.recovery_code?(otp)
      flash.now[:error] = "It looks like you used a recovery code. Please try again with an authentication code."
      return false
    end

    if current_user.valid_otp?(otp, type: credential_type, callsite: "sudo")
      instrument_sudo_prompt(success: true, credential_type: credential_type, result: "success")
      true
    else
      result = "auth_failure"
      if current_user.reused_valid_totp?(otp, type: credential_type)
        message = ["The authentication code you entered has already been used or is too old to be used."]
        result = "old_or_reused_otp"
        if current_user.two_factor_sms_enabled? && credential_type == :sms && otp != current_user.two_factor_sms_totp.now
          begin
            current_user.send_two_factor_sms(callsite: :sudo_authenticate_resend)
            message << "A new code has been sent to your phone."
          rescue GitHub::SMS::Error => e
            message << T.unsafe(self).sms_delivery_error_message(e.message)
          end
        end
        flash.now[:error] = message.join(" ")

        instrument_sudo_prompt(success: false, credential_type: credential_type, result: result)
        false
      else
        real_failure = otp =~ TwoFactorCredential::OTP_REGEX && !current_user.two_factor_recently_valid_otp?(otp)
        @at_auth_limit = true if AuthenticationLimit.at_any?(two_factor_login: current_user.login, increment: real_failure, actor_ip: request.remote_ip) # rubocop:disable GitHub/DoNotAllowLogin login used internally to lookup user see AuthenticationLimit#instrument_lockout
        flash.now[:error] = "Sudo authentication failed."

        instrument_sudo_prompt(success: false, credential_type: credential_type, result: result)
        false
      end
    end
  end

  # Private: Stat sudo prompt results
  def instrument_sudo_prompt(success:, credential_type:, result:)
    GitHub.dogstats.increment("sudo_prompt", tags: ["credential_type:#{credential_type}", "result:#{result}"])
    current_user.instrument_sudo_result(success, { credential_type: credential_type, result: result })
  end
end
