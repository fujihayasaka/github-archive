# typed: true
# frozen_string_literal: true

require "securerandom"
class SessionsController < ApplicationController
  include ApplicationController::GitHubMobileAuthDependency
  include GitHubMobileAuthHelper
  include WebauthnHelper
  include EnterpriseManagedUsersHelper
  include SetLoggedOutCookieConcern
  include Site::MicrosoftAnalyticsDependency

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    only: [:confirm_logout]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Authnd,
    ApplicationRecord::Configurations,
    only: [:new]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Ballast,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    only: [:github_mobile_verified_device_prompt]

  depends_on_clusters ApplicationRecord::Mysql1,
    only: [:verified_device_prompt]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Ballast,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Authnd,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    only: [:github_mobile_two_factor_prompt]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Authnd,
    ApplicationRecord::Collab,
    ApplicationRecord::Ballast,
    ApplicationRecord::IamAbilities,
    only: [:two_factor_prompt, :github_mobile_navigating_away_metrics]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Authnd,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Repositories,
    ApplicationRecord::IamAbilities,
    only: [:two_factor_sms_prompt, :two_factor_app_prompt]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Authnd,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
    only: [:two_factor_sms_confirm]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    only: [:two_factor_recover_prompt]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Authnd,
    only: [:webauthn_prompt]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
    only: [:suspended]

  depends_on_clusters ApplicationRecord::Mysql1,
    only: [:sudo_modal]

  # sessions#create is accessible via a GET route on Enterprise (for CAS)
  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Authnd,
    ApplicationRecord::Collab,
    ApplicationRecord::Ballast,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Migrations,
    ApplicationRecord::Repositories,
    ApplicationRecord::Configurations,
    only: [:create]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Ballast,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Authnd,
    ApplicationRecord::IamAbilities,
    only: [:trusted_device_registration_prompt, :trusted_device_upgrade_prompt]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [
      :github_mobile_verified_device_prompt,
      :two_factor_app_prompt,
      :github_mobile_two_factor_prompt,
      :two_factor_sms_prompt,
      :two_factor_sms_confirm
    ], optional: true

  # Window of time in which a verified device verification code is valid.
  VERIFIED_DEVICE_EXPIRY = 1.hour

  include WebauthnHelper::ControllerMethods
  include CustomMessagesHelper
  include GitHub::RateLimitable

  # This controller does not access protected organization resources.
  skip_before_action :perform_conditional_access_checks # rubocop:disable GitHub/DoNotSkipCapBeforeAction

  # We don't want to show the 2fa requirement interrupt if the user is simply trying to logout.
  skip_before_action :account_2fa_requirement_interrupt, only: [:confirm_logout]
  # We don't want to show the 2FA checkup interrupt if the user is performing other auth, or logout actions.
  skip_before_action :require_two_factor_checkup

  # These actions are rate limited by GitHub::RateLimitedRequest and AuthenticationLimits
  SMS_DELIVERY_ACTIONS = %w(resend_two_factor_sms send_two_factor_fallback_sms)
  OTP_ENTRY_ACTIONS = %w(two_factor_authenticate verified_device_authenticate)
  LOGIN_ACTIONS = %w(new)

  before_action :clear_weak_password_session_variable, only: :new
  before_action :set_return_to,                     only: :create
  before_action :set_first_emu_admin,               only: :create
  before_action :anonymous_required_for_login,      only: :new
  before_action :get_based_sudo_filter,             only: :sudo
  before_action :ensure_two_factor_sms_enabled,     only: %i(resend_two_factor_sms send_two_factor_fallback_sms)
  before_action :authentication_user_required,      only: SMS_DELIVERY_ACTIONS + OTP_ENTRY_ACTIONS
  before_action :login_required,                    only: %i(sudo_modal trusted_device_registration_prompt trusted_device_upgrade_prompt trusted_device_continue trusted_device_decline github_mobile_sudo_prompt github_mobile_sudo_status)
  before_action :set_current_application,           only: %i(create new)
  before_action :unset_application_if_spammy,       only: %i(create new)
  after_action  :update_login_metadata,             only: %i(create two_factor_authenticate webauthn_authenticate two_factor_recover github_mobile_two_factor_status github_mobile_verified_device_status)
  after_action  :clear_browser_cache,               only: :destroy
  before_action :sudo_filter,                       only: [:trusted_device_registration_prompt]
  before_action :repost_saml_response,              only: :create, if: :repost_saml_response?
  before_action :allow_initial_cookie_consent,      only: [:new]
  before_action :enable_microsoft_analytics,        only: [:new]
  before_action :add_microsoft_analytics_csp_exceptions, only: [:new]

  rate_limit_requests except: :resend_verification_email

  layout "layouts/session_authentication"
  javascript_bundle :settings
  javascript_bundle :sessions
  # the signup bundle is required for captcha
  javascript_bundle :signup

  # GitHub Enterprise specific filters
  if GitHub.enterprise?
    # sessions#create is accessible via a GET route on Enterprise (for CAS),
    # so we need to make sure it's always using the write database:
    around_action :select_write_database, only: :create

    before_action :validate_ghes_path_and_params, only: :create

    if GitHub.pages_enabled? && GitHub.subdomain_private_mode_enabled?
      # Add GitHub Enterprise pages domain to the "form-action" directive
      # this allows us to redirect back to a pages domain when logging in
      # see https://github.com/w3c/webappsec-csp/issues/8
      before_action :add_csp_exceptions, only: [:new]
      CSP_EXCEPTIONS = { form_action: [GitHub.pages_host_name_v2] }
    end

    if GitHub.first_run_exempt_from_signup?
      skip_before_action :first_run_check
    end

    skip_before_action :verify_authenticity_token,    only: :create, if: :ghes_saml_request?
  end

  if GitHub.two_factor_sms_enabled?
    before_action :add_csp_exceptions, only: [:two_factor_sms_confirm]
    CSP_EXCEPTIONS = {
      frame_src: [GitHub.urls.octocaptcha_host_name],
    }
  end

  include GitHub::RateLimitedRequest
  rate_limit_requests \
    only: SMS_DELIVERY_ACTIONS + OTP_ENTRY_ACTIONS + LOGIN_ACTIONS,
    if: :should_rate_limit,
    max: :sessions_rate_limit_max,
    ttl: :sessions_rate_limit_ttl,
    key: :sessions_rate_limit_key,
    log_key: "2fa",
    at_limit: :sessions_rate_limit_render,
    render_allow_body: true,
    glb: :sessions_glb

  private def validate_ghes_path_and_params
    if request.path != "/session" && params.key?(:password)
      render_404
    end
  end

  def new
    # Avoid sending the query string to Google Analytics. It might contain a
    # `return_to` param that could be a sensitive URL like a private Gist.
    strip_analytics_query_string

    headers["Cache-Control"] = "no-cache, no-store"

    respond_to do |format|
      format.html do
        if GitHub.auth.external? && GitHub.auth.path
          if GitHub.auth.builtin_auth_fallback? && !params[:force_external]
            render "dashboard/logged_out", locals: { index_page: true }
          else
            external_auth_redirect
          end
        else
          if proxima_login_redirect?
            safe_redirect_to business_idm_sso_enterprise_path(get_current_tenant, return_to: params[:return_to], add_account: params[:add_account])
          elsif emu_header_login_redirect?
            safe_redirect_to business_idm_sso_enterprise_path(business_from_header, return_to: params[:return_to], add_account: params[:add_account])
          else
            # In Proxima, we want to show a new login experience for admins for these scenarios:
            # 1. They are coming from the enterprise SSO page (params[:admin] == "true")
            # 2. This is a brand new tenant and have not enabled an external provider (GitHub.flipper[:proxima_initial_login_experience].enabled?)
            # To note for 2, we don't need to check if the external provider is enabled because that is already checked in line 211.
            proxima_admin_login = GitHub.flipper[:proxima_first_emu_admin_login_experience].enabled? &&
              GitHub.multi_tenant_enterprise? &&
              (params[:admin] == "true" || GitHub.flipper[:proxima_initial_login_experience].enabled?)
            render "sessions/new", locals: { proxima_admin_login: proxima_admin_login, emu_first_admin_login: emu_first_admin_login? }
          end
        end
      end
      format.all { return head :not_acceptable }
    end
  end

  PASSKEY_LOGIN_ERROR = "Unable to sign in with your passkey. Please sign in with your password."
  SECURITY_KEY_LOGIN_ERROR = "This credential can only be used for 2FA. Please sign in with your password."
  PASSKEY_UPGRADE_ERROR = "Unable to upgrade your credential. To register it as a passkey, please delete the existing security key registration."

  def show_webauthn_error(security_key_failure: false) # rubocop:todo GitHub/UseRestfulActions
    if auth_for_passkey_promotion?
      flash[:error] = PASSKEY_UPGRADE_ERROR
    elsif Rails.env.development?
      # you can't develop passkeys without ssl, and anonymous_flash only works on port 80
      flash[:error] = security_key_failure ? SECURITY_KEY_LOGIN_ERROR : PASSKEY_LOGIN_ERROR
    else
      anonymous_flash[:error] = security_key_failure ? SECURITY_KEY_LOGIN_ERROR : PASSKEY_LOGIN_ERROR
    end
    redirect_to_return_to(fallback: "/")
  end

  # passwordless sign-in with a passkey or passkey promotion
  def webauthn_authenticate_passwordless # rubocop:todo GitHub/UseRestfulActions
    result = :failure
    webauthn_failure = nil
    tags = ["action:#{auth_for_passkey_promotion? ? "webauthn_authenticate_confirm" : "webauthn_authenticate_passwordless"}",
      "conditional_mediation:#{params[:"webauthn-conditional"]}", "origin:passwordless_authentication"]
    begin
      sign_response_hash = JSON.parse(params[:webauthn_response])
    rescue JSON::ParserError
      webauthn_failure = :parser_error
      return show_webauthn_error
    end

    sign_response = WebAuthn::AuthenticatorAssertionResponse.new(
      authenticator_data: Base64.urlsafe_decode64(sign_response_hash["response"]["authenticatorData"]),
      signature: Base64.urlsafe_decode64(sign_response_hash["response"]["signature"]),
      client_data_json: Base64.urlsafe_decode64(sign_response_hash["response"]["clientDataJSON"])
    )
    origin = Addressable::URI.new(scheme: request.scheme, host: request.host).to_s
    user, webauthn_failure = resolve_user_handle(sign_response_hash, tags)
    webauthn_failure = :not_allowed if user && !user.passkeys_enabled?
    return show_webauthn_error if webauthn_failure

    if is_enterprise_access_restricted?(user.display_login)
      return render plain: enterprise_access_verification_message(business_from_header), status: 403
    end

    sign_challenge, err = webauthn_sign_challenge_from_request(user)
    if sign_challenge.nil?
      webauthn_failure = err
      return show_webauthn_error
    end
    GitHub.context.push(spamurai_form_signals: spamurai_form_signals)
    GitHub.context.push(visitor_id: current_visitor.id)

    reason = auth_for_passkey_promotion? ? :passkey_promote_confirmation : :passwordless_sign_in
    authenticated_registration = user.webauthn_authenticated_registration(reason, origin, sign_challenge,
        sign_response_hash, sign_response, require_passkey: !auth_for_passkey_promotion?)

    key_handle = sign_response_hash["rawId"]
    security_key = user.u2f_registrations.security_keys.find_by_key_handle(key_handle)
    unless authenticated_registration.present?
      instrument_failed_passkey_login(user: user, reason: :passkey) if !auth_for_passkey_promotion?
      webauthn_failure = security_key.present? ? :require_passkey : :auth_failure
      return show_webauthn_error(security_key_failure: security_key.present?)
    end

    if auth_for_passkey_promotion?
      # if we're trying to promote a credential to passkey, we need to know if it's currently a passkey or security key
      is_passkey_eligible = security_key&.is_passkey_eligible_on_auth?(:confirm, current_device_id)
      passkey = current_user.u2f_registrations.passkeys.find_by_key_handle(key_handle)
      current_device = current_user.authenticated_devices.find_by_device_id(current_device_id)
      is_already_associated = current_user.trusted_device_client_registrations.where(trusted_device: passkey, authenticated_device: current_device).exists?
      tags.concat([
        "passkey:#{!!passkey}",
        "already_associated:#{is_already_associated}",
        "promotable_security_key:#{is_passkey_eligible}",
      ])

      # make sure this is a security key and not us re-registering an existing passkey
      if security_key
        if is_passkey_eligible
          session[:security_key_to_upgrade] = security_key.id
          result = :success
          return render "sessions/webauthn/trusted_device_registration_prompt", locals: { convert_for: security_key, from_settings: from_settings? }
        else
          flash[:error] = "Existing security key '#{security_key.nickname}' isn't passkey eligible."
          return redirect_after_successful_login
        end
      elsif passkey
        # if user is confirming an existing passkey link it to the current device
        associate_trusted_device_with_client(passkey, :webauthn_confirm_existing) unless is_already_associated
        result = :success
        flash[:notice] = "You have already registered '#{passkey.nickname}' as a passkey. You're all set!"
        return redirect_after_successful_login
      end
    end

    if user.suspended?
      # if the user is suspended, we should not allow the user to log in
      webauthn_failure = :suspended_user
      instrument_failed_passkey_login(user: user, reason: :suspended)
      session[:suspended_login] = user.display_login
      return redirect_to suspended_url
    end

    # successful passwordless login
    login_user user, sign_in_verification_method: :passkey, passwordless_credential: authenticated_registration
    associate_trusted_device_with_client(current_user.u2f_registrations.find_by_key_handle(key_handle), :webauthn_authenticate_passwordless)

    set_analytics_dimension(
      name: GoogleAnalytics::Dimensions::HAS_ACCOUNT,
      value: "Logged In",
      redirect: true,
    )

    GitHub.stats.increment "auth.result.success.web" if GitHub.enterprise?
    result = :success
    tags.concat(["passkey:true"])

    redirect_after_successful_login
  ensure
    if result == :failure
      T.must(tags).concat(["reason:#{webauthn_failure}"])
      # log results for failures that don't make it to `user.webauthn_authenticated_registration`
      U2fRegistration.log_result("webauthn_verify_registration_attempt", self.class.name, reason, false, webauthn_failure,
        authenticated_registration, { "gh.request.credential.raw_key_handle": key_handle }) if webauthn_failure != :auth_failure
    end
    GitHub.dogstats.increment("authentication.webauthn", tags: T.must(tags).concat(["result:#{result}"]))
    register_webauthn_client_support(result == :success, webauthn_failure)
  end

  def auth_for_passkey_promotion? # rubocop:todo GitHub/UseRestfulActions
    # passkey promote accepts security keys, passwordless ONLY accepts passkeys
    params[:confirm] && logged_in?
  end

  # Overrides `ApplicationController`.
  # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
  def authentication_user # rubocop:todo GitHub/UseRestfulActions
    return @authentication_user if defined? @authentication_user
    if logged_in?
      @authentication_user = current_user
      return @authentication_user
    end
    @authentication_user = User.find_by_login(session[:two_factor_user])
    @authentication_user ||= User.find_by(id: session[:verified_device_user_id])
  end
  # rubocop:enable GitHub/ControllersShouldUseMemoizeForMemoization

  def external_auth_redirect # rubocop:todo GitHub/UseRestfulActions
    # If we have saml request tracking on, CSRF need to be generated an
    # associated with both client and request. The cookie serves as the
    # client association and the request id to csrf mapping associates
    # the request with csrf token. Together these should ensure we're
    # only accepting requests from the same client.
    #
    # The _legacy cookies are present to work around a bug
    # in Safari 12, where cookies that are marked as
    # SameSite=none are treated as SameSite=strict (https://bugs.webkit.org/show_bug.cgi?id=198181)
    # Since fixes to that bug were not backported to MacOS 10.14, we need to also create
    # cookies without any SameSite attribute at all.
    if GitHub.auth.saml? && GitHub.auth.request_tracking?
      csrf = SecureRandom.urlsafe_base64(80)
      # ForceAuthn when adding an account, to give user the choice of which account in tenant to use.
      # SAML IdP may make the choice of which account to use for the user if force_authn is ForceAuthn not set
      auth_path = GitHub.auth.path(params[:return_to], csrf, params[:add_account] == "1")
      cookies[:saml_csrf_token] = csrf
      cookies[:saml_csrf_token_legacy] = csrf
      cookies[:saml_return_to] = params[:return_to] if params[:return_to]
      cookies[:saml_return_to_legacy] = params[:return_to] if params[:return_to]
    else
      auth_path = GitHub.auth.path(params[:return_to])
    end

    if GitHub.auth.saml?
      redirect_url = auth_path
      render "site/saml_auth_meta_redirect", locals: { redirect_url: redirect_url }, layout: "layouts/redirect"
    else
      redirect_to auth_path
    end
  end

  private def send_device_verification_email(verified_device_user)
    verification_code = AuthenticatedDevice.generate_device_verification_code
    device_name = AuthenticatedDevice.generated_display_name(parsed_useragent)
    current_device = verified_device_user.authenticated_devices.find_by_device_id(session[:device_id])
    verified_device_user.instrument_unverified_device(:device_verification_requested, current_device, method: :email)

    CriticalAccountLoginMailer.verified_device_verification(verified_device_user, device_name, verification_code).deliver_later

    session[:device_verification_code] = verification_code
    session[:device_verification_expiration] = Time.now.to_i + VERIFIED_DEVICE_EXPIRY.to_i
  end

  def verified_device_prompt # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless session[:verified_device_user_id]
    verified_device_user = User.find_by(id: session[:verified_device_user_id])
    send_device_verification_email(verified_device_user) unless session[:device_verification_code]
    render "sessions/verified_device_prompt", locals: { verified_device_user: verified_device_user }
  end

  # this is a GET request which is used to generate a GitHub Mobile verified device challenge
  # and display a prompt to the user
  #
  # `suppress_flash` indicates that the user was automatically redirected here after sign-in.
  def github_mobile_verified_device_prompt # rubocop:todo GitHub/UseRestfulActions
    suppress_flash = params[:auto] == "true"

    # send them through if they just logged in
    if logged_in? && params[:redirect].present?
      return redirect_to_passkey_registration_or_return_to(current_user)
    end

    # otherwise 404 an already logged_in user
    return render_404 if logged_in?

    # check that the user is a partially signed in user
    verified_device_user = User.find_by(id: session[:verified_device_user_id])
    return render_404 unless verified_device_user

    # check that the user can use GitHub Mobile authentication right now
    return redirect_to verified_device_prompt_path unless can_use_gh_mobile_auth?(verified_device_user)

    if !session[:gh_mobile_request_id]
      # instrument event if the user is starting a new request
      current_device = verified_device_user.authenticated_devices.find_by(device_id: session[:device_id])
      verified_device_user.instrument_unverified_device(:device_verification_requested, current_device, method: :github_mobile)
    end
    # the current device will never be verified, so we can't skip the challenge
    skip_challenge = false

    # if request fails, user will be redirected to verified_device_prompt
    success = initiate_mobile_auth_request(:device_verification, verified_device_user, skip_challenge, suppress_flash)
    return redirect_to verified_device_prompt_path if !success

    # render the mobile prompt page with the challenge
    render "sessions/github_mobile/verified_devices_prompt", locals: {
      challenge: session[:gh_mobile_challenge],
      user: verified_device_user,
    }
  end

  def github_mobile_verified_device_status # rubocop:todo GitHub/UseRestfulActions
    # must be an XHR request
    return render_404 unless request.xhr?

    verified_device_user = User.find_by(id: session[:verified_device_user_id])
    result = get_mobile_auth_request_status(:device_verification, verified_device_user)
    return render json: { status: result }, status: :internal_server_error if result == :STATUS_ERROR
    current_device = verified_device_user.authenticated_devices.find_by(device_id: session[:device_id]) if verified_device_user

    case result
    when :STATUS_APPROVED
      login_user verified_device_user, authenticated_device: current_device, sign_in_verification_method: :verified_device
      verified_device_user&.instrument_unverified_device(:device_verification_success, current_device, reason: :gh_mobile_verified_sign_in)
    when :STATUS_REJECTED
      anonymous_flash[:error] = "Sign-in verification failed."
      verified_device_user&.instrument_unverified_device(:device_verification_failure, current_device, reason: :gh_mobile_rejected)
      if AuthenticationLimit.at_any?(verified_device_login: verified_device_user&.login, increment: true, actor_ip: request.remote_ip) # rubocop:todo GitHub/DoNotAllowLogin https://github.com/github/authentication/issues/2400
        # redirect happens in github-mobile-two-factor.ts
        @at_auth_limit = true
      end
    when :STATUS_EXPIRED
      GitHub.dogstats.increment("authenticated_device", tags: ["action:mobile_verification", "error:expired"])
    end

    # if we've made it this far, it's safe to return the status from authnd to the client
    render json: { status: result }
  end

  DEVICE_CODE_RATE_LIMIT_OPTIONS = {
    max_tries: 5,
    ttl: 15.minutes,
  }
  def resend_verification_email # rubocop:todo GitHub/UseRestfulActions
    if session[:device_verification_expiration].blank?
      GitHub.dogstats.increment("authenticated_device", tags: ["action:resend", "error:nil_expiration"])
      anonymous_flash[:notice] = "An unexpected error has occurred, please try signing in again."
      return redirect_to_login
    end

    if session[:device_verification_expiration] < Time.now.to_i
      anonymous_flash[:notice] = "Your device verification code has expired."
      return redirect_to_login
    end

    verified_device_user = User.find(session[:verified_device_user_id])
    rate_limit_key = "verification-code-limit:#{session[:verified_device_user_id]}"
    if rate_limit_increment(rate_limit_key, DEVICE_CODE_RATE_LIMIT_OPTIONS).at_limit?
      @at_auth_limit = true
      return render "sessions/new"
    end

    device_name = AuthenticatedDevice.generated_display_name(parsed_useragent)
    CriticalAccountLoginMailer.verified_device_verification(verified_device_user, device_name, session[:device_verification_code]).deliver_later
    flash[:notice] = "Your code has been resent"
    redirect_to verified_device_prompt_path
  end

  def verified_device_authenticate # rubocop:todo GitHub/UseRestfulActions
    user_id = session[:verified_device_user_id]
    verified_device_user = User.find_by(id: user_id)

    return redirect_to_login unless verified_device_user

    if AuthenticationLimit.at_any?(verified_device_login: verified_device_user.login) # rubocop:todo GitHub/DoNotAllowLogin https://github.com/github/authentication/issues/2400
      @at_auth_limit = true
      return render "sessions/new"
    end

    if session[:device_verification_expiration].blank?
      GitHub.dogstats.increment("authenticated_device", tags: ["action:verification", "error:nil_expiration"])
      anonymous_flash[:notice] = "An unexpected error has occurred, please try signing in again."
      return redirect_to_login
    end

    if session[:device_verification_expiration] < Time.now.to_i
      GitHub.dogstats.increment("authenticated_device", tags: ["action:verification", "error:expired"])
      anonymous_flash[:error] = "Your device verification code has expired."
      return redirect_to_login
    end

    unless SecurityUtils.secure_compare(session[:device_id], current_device_id)
      GitHub.dogstats.increment("authenticated_device", tags: ["action:verification", "error:device_id_mismatch"])
      anonymous_flash[:error] = "Something went wrong, please try signing in again."
      return redirect_to_login
    end

    unless current_device = verified_device_user.authenticated_devices.find_by(device_id: session[:device_id])
      GitHub.dogstats.increment("authenticated_device", tags: ["action:verification", "error:no_device_found"])
      anonymous_flash[:error] = "Something went wrong loading your profile, please try signing in again."
      return redirect_to_login
    end

    if session[:device_verification_code].blank?
      GitHub.dogstats.increment("authenticated_device", tags: ["action:verification", "error:empty_or_nil_verification_code"])
      anonymous_flash[:error] = "Something went wrong validating the verification code, please try signing in again."
      return redirect_to_login
    end

    unless SecurityUtils.secure_compare(session[:device_verification_code], TwoFactorCredential.normalize_otp(params[:otp]))
      if AuthenticationLimit.at_any?(verified_device_login: verified_device_user.login, increment: true, actor_ip: request.remote_ip)  # rubocop:todo GitHub/DoNotAllowLogin https://github.com/github/authentication/issues/2400
        @at_auth_limit = true
        return render "sessions/new"
      else
        verified_device_user.instrument_unverified_device(:device_verification_failure, current_device)
        flash[:error] = "Incorrect verification code provided."
        return redirect_to verified_device_prompt_path
      end
    end

    login_user verified_device_user, authenticated_device: current_device, sign_in_verification_method: :verified_device
    verified_device_user.instrument_unverified_device(:device_verification_success, current_device, reason: :verified_sign_in)
    GitHub.dogstats.increment("authenticated_device.verification_without_verified_email") if GitHub.email_verification_enabled? && verified_device_user.emails.verified.empty?

    redirect_to_passkey_registration_or_return_to(verified_device_user)
  end

  def two_factor_prompt # rubocop:todo GitHub/UseRestfulActions
    @user = User.find_by_login session[:two_factor_user]
    render_two_factor_prompt_for(@user)
  end

  def two_factor_app_prompt # rubocop:todo GitHub/UseRestfulActions
    @user = User.find_by_login session[:two_factor_user]
    return render_404 unless @user
    return render_404 unless @user.two_factor_configured_with?(:app)
    render "sessions/two_factor_app_prompt"
  end

  def two_factor_sms_confirm # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless GitHub.two_factor_sms_enabled?
    @user = User.find_by_login session[:two_factor_user]
    return render_404 unless @user
    return render_404 unless @user.two_factor_sms_enabled?

    @show_captcha = @user.two_factor_sms_requires_captcha?(session, callsite: :two_factor_sms_confirm)

    render "sessions/two_factor_sms_confirm"
  end

  def two_factor_sms_send # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless GitHub.two_factor_sms_enabled?
    @user = User.find_by_login session[:two_factor_user]
    return render_404 unless @user
    return render_404 unless @user.two_factor_sms_enabled?

    requires_captcha = @user.two_factor_sms_requires_captcha?(session, callsite: :two_factor_sms_send)
    completed_captcha = requires_captcha && two_factor_sms_login_captcha_was_verified?

    if requires_captcha && !completed_captcha
      anonymous_flash[:error] = "Unable to verify your captcha answer. " \
        "Please try again or visit #{octocaptcha_help_url} for troubleshooting information."
      return redirect_to two_factor_sms_confirm_path
    end

    @user.send_two_factor_sms(use_alternate_provider = params[:resend] == "true", callsite: :sessions_two_factor_sms_send, completed_captcha: completed_captcha)
    redirect_to two_factor_sms_prompt_path
  rescue GitHub::SMS::Error => e
    flash[:error] = sms_delivery_error_message(e.message)
    # before bumping them right to the recovery code prompt, let's check if they can use an authenticator app instead
    return redirect_to two_factor_app_prompt_path if @user.two_factor_configured_with?(:app)
    redirect_to two_factor_recover_prompt_path
  end

  def two_factor_sms_prompt # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless GitHub.two_factor_sms_enabled?
    @user = User.find_by_login session[:two_factor_user]
    return render_404 unless @user
    return render_404 unless @user.two_factor_sms_enabled?

    render "sessions/two_factor_sms_prompt"
  end

  def two_factor_authenticate # rubocop:todo GitHub/UseRestfulActions
    user_login, otp_retry_allowed = get_partially_authenticated_two_factor_session

    return render_404 unless user_login

    if AuthenticationLimit.at_any?(two_factor_login: user_login)
      @at_auth_limit = true
      return render "sessions/new"
    end

    allow_generic_otp_param = !GitHub.flipper[:disallow_two_factor_login_generic_otp_param].enabled?

    # We are still seeing some users accessing this endpoint with the old/generic "otp" param.
    # We should allow it for now so we don't break them, but ideally we will remove it in the future.
    otp, active_totp_type = GitHub::TwoFactorAuthentication.normalize_otp_from_params(params, allow_generic_otp_param: allow_generic_otp_param, action: "login")

    # Try treating it like a recovery code if it looks right.
    if GitHub::TwoFactorAuthentication.recovery_code?(otp)
      anonymous_flash[:error] = "It looks like you used a recovery code. Please try again with an authentication code."
      # prevent a bad bot from getting into an endless loop
      AuthenticationLimit.at_any?(two_factor_login: user_login, increment: true, actor_ip: request.remote_ip)
      return redirect_to_login
    end

    if otp_retry_allowed && user = User.otp_authenticate(user_login, otp, active_totp_type, callsite: "session", allow_generic: allow_generic_otp_param)
      instrument_two_factor_challenge_success(user: user, type: active_totp_type ? active_totp_type.to_s : "otp")

      login_user user, sign_in_verification_method: :two_factor_user
      GitHub.stats.increment "auth.result.success.web" if GitHub.enterprise?

      user.clear_two_factor_checkup_date

      redirect_to_passkey_registration_or_return_to(user)
    else
      user = User.find_by_login user_login
      unless user.two_factor_authentication_enabled?
        anonymous_flash[:error] = "Two-factor authentication has been disabled for this account. Try signing in again."
        return redirect_to_login
      end

      instrument_two_factor_challenge_failure(user: user, type: active_totp_type ? active_totp_type.to_s : "otp")
      GitHub.stats.increment "auth.result.failure.two_factor.web" if GitHub.enterprise?

      real_failure = otp =~ TwoFactorCredential::OTP_REGEX &&
                     !user.two_factor_recently_valid_otp?(otp)

      at_limit = AuthenticationLimit.at_any?(
        increment: real_failure,
        actor_ip: request.remote_ip,
        two_factor_login: user_login,
      )

      if at_limit
        AccountMailer.two_factor_brute_force(user).deliver_later
        @at_auth_limit = true
        render "sessions/new"
      elsif user.reused_valid_totp?(otp, type: active_totp_type, allow_generic: allow_generic_otp_param)
        set_partially_authenticated_two_factor_session(user)
        message = ["The two-factor code you entered has already been used or is too old to be used."]
        if user.two_factor_sms_enabled? && active_totp_type == :sms && otp != user.two_factor_sms_totp.now
          begin
            user.send_two_factor_sms(callsite: :sessions_two_factor_authenticate_resend)
            message << "A new code has been sent to your phone."
          rescue GitHub::SMS::Error => e
            message << sms_delivery_error_message(e.message)
          end
        end
        flash.now[:error] = message.join(" ")
        render_for_incorrect_otp(user, type: active_totp_type)
      elsif otp_retry_allowed
        flash.now[:error] = "Two-factor authentication failed."
        set_partially_authenticated_two_factor_session(user)
        render_for_incorrect_otp(user, type: active_totp_type)
      else
        anonymous_flash[:error] = "Two-factor authentication failed."
        redirect_to_login
      end
    end
  end

  def webauthn_prompt # rubocop:todo GitHub/UseRestfulActions
    @user = User.find_by_login session[:two_factor_user]
    return render_404 unless @user && @user.has_webauthn_credential?

    render "sessions/webauthn/prompt", locals: { webauthn_user: @user }
  end

  # 2FA sign-in with webauthn
  def webauthn_authenticate # rubocop:todo GitHub/UseRestfulActions
    # Find partially authenticated user.
    user_login, otp_retry_allowed = get_partially_authenticated_two_factor_session
    user = User.find_by(login: user_login)

    # Check they they got here correctly.
    return render_404 unless user

    # Check that they haven't been sitting on the 2FA screen for days.
    return redirect_to_login unless otp_retry_allowed

    # Check that we've got all the data we need to try authenticating.
    sign_response_json_serialized = params[:response]
    challenge, _ = webauthn_sign_challenge_from_request(user)
    unless sign_response_json_serialized.present? && challenge
      return render_two_factor_prompt_for(user)
    end

    origin = Addressable::URI.new(scheme: request.scheme, host: request.host).to_s
    authenticated_registration = user.webauthn_json_authenticated_registration(:two_factor_sign_in, origin, challenge, sign_response_json_serialized)
    if authenticated_registration
      is_passkey = authenticated_registration.is_passkey_registration?
      instrument_two_factor_challenge_success(user: user, type: is_passkey ? "passkey" : "u2f", payload: { credential_id: authenticated_registration.id, credential_nickname: authenticated_registration.nickname })

      login_user user, sign_in_verification_method: :two_factor_user
      GitHub.stats.increment "auth.result.success.web" if GitHub.enterprise?

      if is_passkey
        associate_trusted_device_with_client(authenticated_registration, :webauthn_authenticate)
      end

      sign_response_hash = JSON.parse(sign_response_json_serialized)
      security_key = current_user.u2f_registrations.security_keys.find_by_key_handle(sign_response_hash["rawId"])
      session[:security_key_to_upgrade] = security_key.id if security_key&.is_passkey_eligible_on_auth?(:login_2fa, current_device_id)
      redirect_to_passkey_registration_or_return_to(user)
    else
      instrument_two_factor_challenge_failure(user: user, type: T.unsafe(is_passkey) ? "passkey" : "u2f")
      flash[:error] = "Security key authentication failed."
      set_partially_authenticated_two_factor_session(user)
      render_two_factor_prompt_for(user)
    end
  end

  # this is a GET request which is used to generate a GitHub Mobile 2fa challenge
  # and display a prompt to the user
  #
  # `suppress_flash` indicates that the user was automatically redirected to the GitHub Mobile 2FA page during login and the user did not set their 2FA preference.
  # When authnd fails and `suppress_flash` is false, they will be automatically be redirected to the TOTP 2FA page and shown the flash error message.
  def github_mobile_two_factor_prompt # rubocop:todo GitHub/UseRestfulActions
    suppress_flash = params[:auto] == "true"

    # if the user is logged in and the redirect query param is present
    # send them through with a redirect and potentially show them the trusted_device registration prompt
    if logged_in? && params[:redirect].present?
      return redirect_to_passkey_registration_or_return_to(current_user)
    end

    # if the user is already logged in, and tries to access this page directly, give them a 404
    return render_404 if logged_in?

    # check that the user is a partially signed in two factor user
    @user = User.find_by_login session[:two_factor_user]
    return render_404 unless @user

    # check that the user can use GitHub Mobile two factor authentication right now
    unless can_use_gh_mobile_auth?(@user)
      return render_two_factor_prompt_for(@user)
    end

    # only skip the challenge if the current device is verified
    skip_challenge = current_device(@user)&.verified? ? true : false

    success = initiate_mobile_auth_request(:two_factor_login, @user, skip_challenge, suppress_flash)
    unless success
      return render_two_factor_prompt_for(@user)
    end

    # render the mobile prompt page with the challenge
    render "sessions/github_mobile/two_factor_prompt", locals: {
      challenge: session[:gh_mobile_challenge],
      user: @user,
    }
  end

  def github_mobile_two_factor_status # rubocop:todo GitHub/UseRestfulActions
    # must be an XHR request
    return render_404 unless request.xhr?
    @user = User.find_by_login session[:two_factor_user]
    result = get_mobile_auth_request_status(:two_factor_login, @user)
    # return early if we cleared out a stale auth request
    return render json: { status: result }, status: :internal_server_error if result == :STATUS_ERROR

    case result
    when :STATUS_APPROVED
      # if the status is approved, log the user in!
      # the user will be redirected once the status is sent down to the client
      instrument_two_factor_challenge_success(user: @user, type: "github_mobile")
      login_user @user, sign_in_verification_method: :two_factor_user
    when :STATUS_REJECTED
      anonymous_flash[:error] = "Two-factor authentication failed."
      instrument_two_factor_challenge_failure(user: @user, type: "github_mobile")
      session.delete(:two_factor_user)

      if AuthenticationLimit.at_any?(increment: true, actor_ip: request.remote_ip, two_factor_login: @user.login) # rubocop:todo GitHub/DoNotAllowLogin https://github.com/github/authentication/issues/2400
        # redirect happens in github-mobile-two-factor.ts
        @at_auth_limit = true
        AccountMailer.two_factor_brute_force(@user).deliver_later
      end
    when :STATUS_EXPIRED
      GitHub.dogstats.increment("two_factor", tags: ["action:challenge", "result:expired", "two_factor_type:github_mobile"])
    end

    # if we've made it this far, it's safe to return the status from authnd to the client
    render json: { status: result }
  end

  def github_mobile_sudo_prompt # rubocop:todo GitHub/UseRestfulActions
    # must be an XHR request
    return render_404 unless request.xhr?

    # these endpoints aren't available in enterprise since GitHub Mobile is not available there
    return head :not_found if GitHub.enterprise?

    # check that the user can use GitHub Mobile sudo authentication, otherwise 404
    return head :not_found unless user_and_session_can_use_gh_mobile_auth?(current_user)

    return head :too_many_requests if AuthenticationLimit.at_any?(two_factor_login: current_user.login) # rubocop:todo GitHub/DoNotAllowLogin https://github.com/github/authentication/issues/2400

    # we always require a challenge for the sudo prompt since it's in a more vulnerable context
    skip_challenge = false
    success = initiate_mobile_auth_request(:sudo, current_user, skip_challenge, false)
    return head 500 if !success

    render(json: { challenge: session[:gh_mobile_challenge] }, status: :ok)
  end

  def github_mobile_sudo_status # rubocop:todo GitHub/UseRestfulActions
    # must be an XHR request
    return render_404 unless request.xhr?

    # these endpoints aren't available in enterprise since GitHub Mobile is not available there
    return head :not_found if GitHub.enterprise?

    result = get_mobile_auth_request_status(:sudo, current_user)
    return render json: { status: result }, status: :internal_server_error if result == :STATUS_ERROR

    case result
    when :STATUS_APPROVED
      instrument_sudo_prompt(success: true, credential_type: "github_mobile", result: "success")
      enable_sudo
    when :STATUS_REJECTED
      @at_auth_limit = true if AuthenticationLimit.at_any?(two_factor_login: current_user.login, increment: true, actor_ip: request.remote_ip) # rubocop:todo GitHub/DoNotAllowLogin https://github.com/github/authentication/issues/2400
      instrument_sudo_prompt(success: false, credential_type: "github_mobile", result: @at_auth_limit ? "exceeded_attempts" : "rejected")
    when :STATUS_EXPIRED
      instrument_sudo_prompt(success: false, credential_type: "github_mobile", result: "expired")
    end

    # if we've made it this far, it's safe to return the status from authnd to the client
    render json: { status: result }
  end

  def two_factor_recover_prompt # rubocop:todo GitHub/UseRestfulActions
    @user = User.find_by_login session[:two_factor_user]
    return render_404 unless @user

    render "sessions/two_factor_recover_prompt"
  end

  def trusted_device_registration_prompt # rubocop:todo GitHub/UseRestfulActions
    return redirect_to_return_to(fallback: home_path) unless current_user&.passkeys_enabled?
    session[:return_to] = params[:return_to] if !!params[:return_to]
    session.delete(:security_key_to_upgrade) if params[:reset]

    if session[:security_key_to_upgrade]
      security_key = current_user.u2f_registrations.security_keys.find_by_id(session[:security_key_to_upgrade])
    end

    existing_security_key_count = 0
    existing_passkey_count = 0

    current_user.u2f_registrations.pluck(:is_passkey_registration).each do
      |is_passkey_registration| is_passkey_registration ? existing_passkey_count += 1 : existing_security_key_count += 1
    end

    render "sessions/webauthn/trusted_device_registration_prompt", locals: {
      convert_for: security_key,
      from_settings: from_settings?,
      existing_security_key_count: existing_security_key_count,
      existing_passkey_count: existing_passkey_count,
    }
  end

  def trusted_device_upgrade_prompt # rubocop:todo GitHub/UseRestfulActions
    return redirect_to_return_to(fallback: home_path) unless current_user&.passkeys_enabled?

    security_key = current_user.u2f_registrations.find_by_id!(params[:id])
    session[:security_key_to_upgrade] = security_key.id
    session[:return_to] = settings_security_path

    render "sessions/webauthn/trusted_device_registration_prompt",
      locals: { convert_for: security_key, from_settings: true }
  end

  # Used for:
  # - successful registration
  # - successful "upgrade" from security key
  def trusted_device_continue # rubocop:todo GitHub/UseRestfulActions
    session.delete(:security_key_to_upgrade) if session[:security_key_to_upgrade]
    if new_registration_id = session.delete(:new_passkey_id)
      nickname = params[:nickname].to_s.strip
      nickname_available = current_user.u2f_registrations.where(nickname: nickname).where.not(id: new_registration_id).empty?
      passkey = current_user.u2f_registrations.passkeys.find_by_id(new_registration_id)

      # The model requires that the nickname is unique. By this point the flow should ensure that
      # the user has provided a unique nickname but we should double check that here
      if nickname.present? && nickname_available
        passkey.update(nickname: nickname) if passkey
      else
        flash[:error] = "There was an error setting your passkey's nickname, it was saved as #{passkey&.nickname}"
      end
    end

    redirect_to_return_to(fallback: "/")
  end

  # Used for:
  # - "ask me later"
  # - "Don't ask again for this browser"
  def trusted_device_decline # rubocop:todo GitHub/UseRestfulActions
    session.delete(:security_key_to_upgrade) if session[:security_key_to_upgrade]
    redirect_to :back unless current_user&.passkeys_enabled?

    hard_decline = params[:hard] # stop showing passkey promote after login for this device id
    # Used by redirect_to_passkey_registration_or_return_to()
    current_device(current_user)&.update!(trusted_device_available: false) if hard_decline
    redirect_to_return_to(fallback: "/")
  end

  def two_factor_recover # rubocop:todo GitHub/UseRestfulActions
    unless user_login = session.delete(:two_factor_user)
      return render_404
    end

    if AuthenticationLimit.at_any?(two_factor_login: user_login)
      @at_auth_limit = true
      render "sessions/new"
    elsif user = User.two_factor_authenticate_with_recovery(user_login, params[:recovery_code])
      instrument_two_factor_recover(user)

      login_user user, sign_in_verification_method: :two_factor_user
      flash[:notice] = "Having trouble with two-factor authentication? You can update your settings here"
      redirect_to settings_security_path
    else
      AuthenticationLimit.at_any?(two_factor_login: user_login, increment: true, actor_ip: request.remote_ip)
      unauthenticated_user = User.find_by_login(user_login)
      GitHub.dogstats.increment("two_factor", tags: ["action:recover", "result:failure"])
      instrument_two_factor_challenge_failure(user: unauthenticated_user, type: "recovery code")
      anonymous_flash[:error] = "Recovery code authentication failed."
      redirect_to_login
    end
  end

  private def ghes_saml_request?
    return false unless GitHub.enterprise? && GitHub.auth.saml?
    return false unless request.post? && request.path == "/saml/consume"

    true
  end

  # Repost is necessary for SAML requests, b/c requests from IdPs don't include SameSite cookies.
  # This check only applies to GHES b/c other envs handle SAML in other controllers.
  # Only need to repost once - skip if `reposted_saml_response` cookie is set b/c that means we've already done a repost
  private def repost_saml_response?
    return false unless ghes_saml_request?
    return false if logged_in? || session.delete(:reposted_saml_response)

    true
  end

  # Same purpose and uses same view as app/controllers/businesses/identity_management/saml_controller.rb#repost_saml_response.
  # For some functionality (Account Switcher), local cookies are necessary but SAML requests from IdPs won't include them
  # due to SameSite cookie policies.
  # So we capture the SAML request, and re-post it but from our own server so SameSite cookies will be included.
  def repost_saml_response # rubocop:todo GitHub/UseRestfulActions
    session[:reposted_saml_response] = true

    form_data = {
      "SAMLResponse" => params[:SAMLResponse],
      "RelayState" => params[:RelayState],
      "_target" => "/saml/consume",
    }

    view = create_view_model(Businesses::IdentityManagement::ReplayEnforcedRequestView, {
      business: nil,
      form_data: form_data
    })
    render "businesses/identity_management/replay_enforced_request",
      locals: { view: view },
      layout: "layouts/session_authentication"
  end

  def create
    if is_enterprise_access_restricted? && !params[:webauthn_response]
      return render plain: enterprise_access_verification_message(business_from_header), status: 403
    end

    if business_by_login_shortcode.present?
      if emu_login?
        sso_params = { return_to: params[:return_to] }
        if emu_login_add_account_for_business? || params[:add_account] == "1"
          sso_params[:add_account] = "1"
        end

        if Rails.env.development?
          unless business_by_login_shortcode.feature_enabled?(:emu_dev_bootstrap)
            redirect_to business_idm_sso_enterprise_path(business_by_login_shortcode, **sso_params)
            return
          end
        else
          redirect_to business_idm_sso_enterprise_path(business_by_login_shortcode, **sso_params)
          return
        end
      elsif emu_first_admin_login?
        if !params[:return_to] || params[:return_to] == "/" || Addressable::URI.parse(params[:return_to]).path == login_path
          session[:return_to] = if !business_by_login_shortcode.external_provider_enabled? || business_by_login_shortcode.find_emu_owners_except_first.count == 0
            enterprise_getting_started_path(business_by_login_shortcode)
          else
            enterprise_path(business_by_login_shortcode)
          end
        end
      end
    end

    if !!params[:webauthn_response]
      webauthn_authenticate_passwordless
    else
      create_session
    end
  end

  def create_session # rubocop:todo GitHub/UseRestfulActions
    # This can happen for external auth modes when return_to is recorded as,
    # for example, "/saml/consume" which would redirect back here as a GET
    # request. Only for saml right now.
    if request.get? && GitHub.auth.saml?
      redirect_to dashboard_url
      return
    end

    # This endpoint is shared by both built-in and saml auth (/login,
    # /saml/consume). This ensures the /saml/consume route is unavailable unless
    # saml auth is configured.
    if request.path == "/saml/consume" && !GitHub.auth.saml?
      render_404 and return
    end

    # While not strictly necessary, we clear out the cookie session context for
    # each login attempt just to be safe.
    persistent_reset_session

    logout_user(:legacy_switched_users) unless account_switcher_helper.enabled?
    GitHub.context.push(spamurai_form_signals: spamurai_form_signals)
    GitHub.context.push(visitor_id: current_visitor.id)

    result, attempted_user = GitHub.auth.rails_authenticate(
      request,
      octolytics_id: current_visitor.octolytics_id,
      current_device_id: current_device_id,
    )
    Failbot.push "gh.user.id": result.user.id if result.user
    GitHub.current_span&.add_attributes({ "gh.auth.result" => result.success ? "success" : "failure", "gh.auth.failure.type" => result.failure_type.to_s })

    register_webauthn_client_support(result.success?, result.failure_type)

    set_from_gh_mobile_session

    # if the user is _adding_ an account and attempts to add an account
    # that they are either actively signed in to or already added, redirect them with a message
    if attempted_user&.id && account_switcher_helper.enabled?
      if logged_in? && current_user&.id == attempted_user.id
        GitHub.dogstats.increment("account_switcher.add_account_post", tags: [
          "result:failure",
          "reason:current_user"
        ])
        flash[:error] = "You're already signed in to this account."
        return redirect_to_login(params[:return_to])
      end
      if account_switcher_helper.account_already_exists?(attempted_user.id)
        GitHub.dogstats.increment("account_switcher.add_account_post", tags: [
          "result:failure",
          "reason:already_added"
        ])
        flash[:notice] = "The account you were attempting to add has already been added. Select it below to switch to it."
        return redirect_to list_accounts_path(return_to: params[:return_to])
      end
      if account_switcher_helper.at_account_maximum?
        if !account_switcher_helper.invalid_account_already_exists?(attempted_user.display_login)
          GitHub.dogstats.increment("account_switcher.add_account_post", tags: [
            "result:failure",
            "reason:maximum_accounts"
          ])
          flash[:error] = "The maximum number of accounts have already been added. Remove an account to add a new one."
          return redirect_to list_accounts_path
        end
      end
    end

    if logged_in? && account_switcher_helper.enabled?
      # mark the current user_sesson as not in use before creating session for user we're adding. We need this here
      # in addition to login_user because of partial sign-ins for 2FA, verified devices, etc.
      user_session.in_use = false
      user_session.save

      # tell front-end to clear local storage
      set_logged_out_cookie
    end

    if Rails.env.development? && GitHub.multi_tenant_enterprise? && !attempted_user.nil? && attempted_user.enterprise_managed_business.nil?
      proxima_message = "User has invalid business id, please include tenant suffix in username.
Alternatively, for proxima login experience run `script/multi-tenant/toggle-feature-flags enable`."
      render plain: proxima_message, status: 403 and return
    end

    # User is authenticated.
    if result.success?
      login_user(
        result.user,
        authenticated_device: result.authenticated_device,
        sign_in_verification_method: result.sign_in_verification_method,
      )

      set_analytics_dimension(
        name: GoogleAnalytics::Dimensions::HAS_ACCOUNT,
        value: "Logged In",
        redirect: true,
      )

      if GitHub.auth.saml? && GitHub.auth.request_tracking?
        request.env["return_to"] = cookies[:saml_return_to] || cookies[:saml_return_to_legacy]
        remove_saml_cookies
      end

      redirect_to_passkey_registration_or_return_to(result.user)
    elsif result.suspended_failure?
      attempted_user && attempted_user.revoke_active_sessions(:suspended)

      # Despite account being suspended a successful login event should be recorded
      # to hydro for abuse detection.
      attempted_user && GlobalInstrumenter.instrument("user.successful_login", {
        actor: attempted_user,
        primary_email: attempted_user.primary_user_email,
        elected_to_receive_marketing_email: nil,
        return_to: session[:return_to],
        authentication_record: nil,
      })

      # When an EMU business is deleted, the first EMU owner is suspended and can't log in. Hence,
      # an appropriate error message explaining why they can't log in should be shown.
      if business = Business.soft_deleted_businesses_for(attempted_user, emu_admin: true).first
        flash[:error] = "Account suspended by deletion of the #{business.slug} enterprise."
        render "sessions/new"
      # When an EMU business trial expires or is cancelled, the first EMU owner is suspended and can't log in.
      elsif business = Business.cancelled_trial_businesses_for(attempted_user, emu_admin: true).first
        flash[:error] = "Account suspended by cancellation of the #{business.slug} enterprise trial."
        render "sessions/new"
      else
        session[:suspended_login] = attempted_user.display_login if attempted_user
        return redirect_to suspended_url
      end
    elsif result.weak_password_failure?
      reset = PasswordReset.new(user: result.user, forced_weak_password_reset: true)
      if reset.valid?
        device = current_device(reset.user)

        if device.nil?
          GitHub.dogstats.increment("auth.compromised_password.blocked_sign_in", tags: ["result:unknown_device"])
          anonymous_flash[:error] = reset.weak_password_reset_message
          redirect_to password_reset_path
        elsif device.verified?
          GitHub.dogstats.increment("auth.compromised_password.blocked_sign_in", tags: ["result:verified_device"])
          safe_redirect_to reset.link
        else
          GitHub.dogstats.increment("auth.compromised_password.blocked_sign_in", tags: ["result:unrecognized_device"])
          anonymous_flash[:error] = reset.weak_password_reset_message
          redirect_to password_reset_path
        end
      else
        GitHub.dogstats.increment("auth.compromised_password.blocked_sign_in", tags: ["result:invalid"])
        Failbot.push("gh.user.id": reset.user.id) # rubocop:disable GitHub/DoNotAllowLogin login is expected in failbot calls
        anonymous_flash[:error] = "#{PasswordReset::FORCED_WEAK_PASSWORD_RESET_MESSAGE} We were unable to find a valid email address on file. Please contact GitHub support to sign in."
        redirect_to_login
      end
    elsif result.unverified_device_failure?
      session[:device_id] = current_device_id
      session[:verified_device_user_id] = result.user.id

      if can_use_gh_mobile_auth?(result.user)
        redirect_to github_mobile_verified_device_prompt_path(auto: true)
      else
        send_device_verification_email(result.user)
        redirect_to verified_device_prompt_path
      end
    # User needs to authenticate with second factor.
    elsif result.two_factor_partial_sign_in?
      # If the user is a first emu admin and they do not have 2FA enabled,
      # we need to redirect this user to the recovery code page.
      #
      # The first emu admin will not be fully authenticated until they enter a recovery code.
      if result.failure_reason == :first_emu_admin_recovery_code_required
        business = result.user.enterprise_managed_business
        session[:recovery_code_required_user] = result.user.login # rubocop:todo GitHub/DoNotAllowLogin
        session[:recovery_code_required_user_id] = result.user.id

        # Clear current user for single sign on recovery code redirect.
        # Ensures audit logs does not get associated with the wrong user.
        user_session_cookies_delete if logged_in? && account_switcher_helper.enabled?

        if business.saml_sso_enabled?
          return redirect_to idm_saml_recover_enterprise_path(business)
        else
          return redirect_to idm_oidc_recover_enterprise_path(business)
        end
      else
        set_partially_authenticated_two_factor_session(result.user)
        # We're going to mark the session as "Logged In" even though user hasn't completed 2FA,
        # because at this point we at least know that they have an account.

        set_analytics_dimension(
          name: GoogleAnalytics::Dimensions::HAS_ACCOUNT,
          value: "Logged In",
          redirect: true,
        )

        # clear the current user for the 2FA redirect so that we use the new, partially
        # authenticated user.  However, leave the saved_user_sessions cookie intact.
        if logged_in? && account_switcher_helper.enabled?
          user_session_cookies_delete
          return two_factor_redirect(user: attempted_user)
        end
        two_factor_redirect
      end
    elsif result.external_response_ignored?
      external_auth_redirect

    # Authentication failed and should be tried again.
    else
      message = result.message || "Incorrect username or password."

      remove_saml_cookies if GitHub.auth.saml?

      if result.at_auth_limit_failure?
        # View has special message exceeded auth limits.
        message = nil
        @at_auth_limit = true
      elsif result.password_failure?
        session[:failed_auth_email] = params[:login] if params[:login].match(User::EMAIL_REGEX)
      elsif attempted_user && attempted_user.organization?
        # View has special message for org attempts.
        message = nil
        @tried_signing_into_org = true
      end

      if GitHub.auth.redirect_on_failure?
        anonymous_flash[:message] = message
        redirect_to GitHub.auth.path
      elsif GitHub.auth.saml? || GitHub.auth.cas?
        flash.now[:error] = message
        render "dashboard/logged_out", locals: { index_page: true }
      else
        proxima_admin_login = GitHub.flipper[:proxima_first_emu_admin_login_experience].enabled? && GitHub.multi_tenant_enterprise? && business_by_login_shortcode.present? && emu_first_admin_login?
        flash.now[:error] = message

        render "sessions/new", locals: { proxima_admin_login: proxima_admin_login }
      end
      # Terminate the worker in the event of an LDAP timeout to prevent any
      # inconsistencies that may occur due to the timeout.
      Process.kill("QUIT", Process.pid) if result.ldap_timeout?
    end

    # We set the session variable here as result.success? || result.two_factor_failure
    # has already been checked in attempt.rb to set compromised_password to be true,
    # it is also to prevent repeating the check in two places in the controller.
    session[::CompromisedPassword::WEAK_PASSWORD_KEY] = result.has_compromised_password.present?
  end

  if GitHub.enterprise?
    # For external auth providers to kick off the auth request
    def external_provider # rubocop:todo GitHub/UseRestfulActions
      render_404
    end
  end

  def confirm_logout # rubocop:todo GitHub/UseRestfulActions
    return redirect_to home_path unless logged_in? || account_switcher_helper.stashed_accounts.any?
    if account_switcher_helper.enabled?
      render "sessions/logout"
    else
      render "sessions/confirm_logout"
    end
  end

  def destroy
    if params[:destroy_all] == "true"
      destroy_all
    elsif params[:user_session_id]
      destroy_saved_session
    else
      destroy_current_session
    end
  end

  private def destroy_current_session
    logout_result = GitHub.auth.rails_logout(request, current_user, redirect_to: redirect_to_for_destroy)

    if logout_result.success?
      GitHub.dogstats.increment("sessions_controller.destroy", tags: [
        "account_switcher_enabled:#{account_switcher_helper.enabled?}",
        "destroy_all:false",
        "account_type:active",
        "result:success",
      ])

      clear_weak_password_session_variable
      Rails.logger.info [Time.now, :auth_mode, GitHub.auth_mode, :params, params].inspect
      flash[:stale_session_signedin] = "SIGNED_OUT"
      session.delete(:return_to)

      if !logged_in?
        return redirect_to "/"
      else
        @logged_out_user = current_user
        delete_saved_user_session_keys(cookies[:user_session])
        logout_user(:logout)
        set_logged_out_cookie
        @logged_out_user.instrument :logout
      end

      if no_saved_sessions_after_destroy?
        anonymous_flash.update(logout_result.flash)
      else
        anonymous_flash[:notice] = "Successfully signed out of @#{@logged_out_user.display_login}."
      end
      redirect_to logout_result.redirect_to
    end
  end

  private def destroy_saved_session
    tags = [
        "account_switcher_enabled:true",
        "destroy_all:false",
        "account_type:stashed",
    ]

    unless account_switcher_helper.enabled?
      flash[:error] = "We were unable to sign out. Please reload the page and try again."
      return head :bad_request
    end

    target_session_id = params[:user_session_id].to_i
    if logged_in? && target_session_id == user_session.id
      return destroy_current_session
    end

    target_stashed_account = account_switcher_helper.stashed_accounts.valid.find do |account|
      account.user_session&.id == target_session_id
    end
    unless target_stashed_account
      GitHub.dogstats.increment("sessions_controller.destroy", tags: tags.concat([
        "result:failed",
        "error:invalid_session_id",
      ]))

      flash[:error] = "We were unable to sign you out of that account. Please reload the page and try again."
      return head :bad_request
    end
    target_user_session = target_stashed_account.user_session
    target_user_session_key = target_stashed_account.user_session_key

    logout_result = GitHub.auth.rails_logout(request, T.unsafe(target_user_session).user, redirect_to: redirect_to_for_destroy)

    if logout_result.success?
      GitHub.dogstats.increment("sessions_controller.destroy", tags: tags.concat(["result:success"]))

      Rails.logger.info [Time.now, :auth_mode, GitHub.auth_mode, :params, params].inspect
      session.delete(:return_to)

      @logged_out_user = T.unsafe(target_user_session).user
      delete_saved_user_session_keys(target_user_session_key)
      logout_user(:logout, target_user_session: target_user_session)
      @logged_out_user.instrument :logout, actor: @logged_out_user
    end

    flash[:notice] = "Successfully signed out of @#{@logged_out_user.display_login}." unless no_saved_sessions_after_destroy?
    redirect_to logout_result.redirect_to
  end

  private def destroy_all
    unless account_switcher_helper.enabled?
      flash[:error] = "We were unable to sign out. Please reload the page and try again."
      return head :bad_request
    end

    # logout of all valid stashed accounts
    account_switcher_helper.stashed_accounts.valid.each do |stashed_account|
      logout_result = GitHub.auth.rails_logout(request, stashed_account.user)
      if logout_result.success?
        GitHub.dogstats.increment("sessions_controller.destroy", tags: [
          "account_switcher_enabled:true",
          "destroy_all:true",
          "account_type:stashed",
          "result:success",
        ])

        logout_user(:logout, target_user_session: stashed_account.user_session)
        stashed_account.user.instrument :logout, actor: stashed_account.user
      end
    end

    delete_saved_user_sessions_cookie
    destroy_current_session
  end

  private def redirect_to_for_destroy
    # for GHES, going to home path can result in forced SAML auth, so always direct to a view to prevent infinite login loop
    logged_out_path = GitHub.enterprise? && GitHub.auth.saml? ? "/dashboard/logged_out" : home_path

    if params[:after_logout].present?
      # follow the redirect specified by the callsite, if provided
      return params[:after_logout]

    elsif no_saved_sessions_after_destroy?
      # user will be left with no accounts after this signout
      return logged_out_path

    elsif params[:user_session_id] && params[:user_session_id]&.to_i != user_session&.id
      # logging out of a stashed account, so give the user the opportunity to remove more
      return confirm_logout_path

    elsif account_switcher_helper.enabled?
      # logging out of active account, so give the user the opportunity to switch accounts
      # once they have switched accounts, they will be redirected to the home page
      return list_accounts_path(return_to: home_path)
    end

    logged_out_path
  end

  private def no_saved_sessions_after_destroy?
    return true if params["destroy_all"] == "true"

    accounts_before_destroy = account_switcher_helper.stashed_accounts.all.size
    accounts_before_destroy += 1 if logged_in?
    accounts_before_destroy <= 1
  end

  def remove_inactive # rubocop:todo GitHub/UseRestfulActions
    return head :not_found unless account_switcher_helper.enabled?

    target = params[:user_session_key]
    unless target
      GitHub.dogstats.increment("sessions_controller.remove_inactive", tags: ["result:failed", "error:missing_param"])
      flash[:error] = "Unable to remove account. Please reload the page and try again."
      return head :bad_request
    end

    if result = UserSession.authenticate(target)
      # we cannot remove a valid session, user should be calling destroy instead.
      GitHub.dogstats.increment("sessions_controller.remove_inactive", tags: ["result:failed", "error:valid_session_key"])
      flash[:error] = "Unable to remove account. Please reload the page and try again."
      return head :bad_request
    end

    target_session = account_switcher_helper.stashed_accounts.all.find { |account| target == account.user_session_key }
    unless target_session
      GitHub.dogstats.increment("sessions_controller.remove_inactive", tags: ["result:failed", "error:session_not_stashed"])
      flash[:error] = "Unable to remove account. Please reload the page and try again."
      return head :bad_request
    end
    target_user = target_session.user

    GitHub.dogstats.increment("sessions_controller.remove_inactive", tags: ["result:success"])
    delete_saved_user_session_keys(target)

    other_accounts_stashed = account_switcher_helper.stashed_accounts.all.any? { |account| target != account.user_session_key }
    if logged_in? || other_accounts_stashed
      flash[:notice] = "Successfully removed @#{target_user.display_login} from your account list."
      return redirect_to confirm_logout_path
    end

    redirect_to_return_to(fallback: home_path)
  end

  def sudo_modal # rubocop:todo GitHub/UseRestfulActions
    render "sudo/sudo_modal", layout: false
  end

  def sudo # rubocop:todo GitHub/UseRestfulActions
    return head 200 if request.xhr?
    return render_404 if params[:sudo_return_to].nil?
    safe_redirect_to params.delete(:sudo_return_to)
  end

  def in_sudo # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless request.format.json?
    render json: valid_sudo_session?
  end

  def kill_sudo # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless current_user&.employee?
    user_session.expire_sudo
    render plain: "no mas sudo"
  end

  def resend_two_factor_sms # rubocop:todo GitHub/UseRestfulActions
    user = logged_in? ? current_user : User.find_by_login(session[:two_factor_user])

    if user && user.two_factor_authentication_enabled? && !user.two_factor_sms_requires_captcha?(session, callsite: :resend_two_factor_sms)
      if user.two_factor_sms_enabled?
        user.send_two_factor_sms(use_alternate_provider = true, callsite: :sessions_resend_two_factor_sms)
        GitHub.dogstats.increment(!logged_in? ? "two_factor" : "two_factor_checkup", tags: ["action:resent_otp", "result:success", "two_factor_type:sms"])
      end
      render_code_sent(user)
    else
      render plain: "", status: 403
    end
  rescue GitHub::SMS::Error => e
    render_code_not_sent(user, sms_delivery_error_message(e.message))
  end

  def send_two_factor_fallback_sms # rubocop:todo GitHub/UseRestfulActions
    user = logged_in? ? current_user : User.find_by_login(session[:two_factor_user])

    if user && user.two_factor_authentication_enabled?
      if user.two_factor_sms_fallback_enabled?
        user.send_two_factor_fallback_sms(!logged_in? ? :sign_in : :checkup)
      end
      render_code_sent(user)
    else
      render plain: "", status: 403
    end
  rescue GitHub::SMS::Error => e
    render_code_not_sent(user, sms_delivery_error_message(e.message))
  end

  def suspended # rubocop:todo GitHub/UseRestfulActions
    if !valid_suspended_referrer
      return redirect_to home_url unless current_user&.suspended?
    end

    @message = customized(:suspended_message)
    if @message.blank?
      @message = default_suspended_message
    end

    render "sessions/suspended"
  end

  # need to make suspended page accessible even when logged in (account switching from legit account to suspended account)
  # but only allow accessing page from login process, to avoid accidentally navigating to it any other time
  private def valid_suspended_referrer
    request.referrer&.start_with?(login_url) ||
    request.referrer&.start_with?(session_url) ||
    # would prefer `request.referrer&.start_with?(saml_consume_url)` but sorbet problems, so this for now
    (GitHub.enterprise? && request.referrer.start_with?("#{GitHub.scheme}://#{GitHub.host_name}/saml/consume"))
  end

  if GitHub.private_mode_enabled?
    # nginx will redirect to this endpoint if an Enterprise subdomain request
    # isn't authenticated. `touch_user_session` will fixup the domain on the
    # cookie for us.
    def auth_request_bounce # rubocop:todo GitHub/UseRestfulActions
      unless logged_in?
        return redirect_to_login(params[:return_to])
      end

      redirect_to_return_to
    end
  end

  # updating github_mobile_two_factor.navigating_away metrics when the user navigates away from a mobile auth page
  def github_mobile_navigating_away_metrics # rubocop:todo GitHub/UseRestfulActions
    paths = {
      two_factor_recover_prompt: two_factor_recover_prompt_path,
      two_factor_prompt: two_factor_prompt_path,
      two_factor_app_prompt: two_factor_app_prompt_path,
      two_factor_sms_prompt: two_factor_sms_prompt_path,
      two_factor_sms_confirm: two_factor_sms_confirm_path,
      webauthn_prompt: webauthn_prompt_path,
      verified_devices_prompt: verified_device_prompt_path,
      unknown: two_factor_prompt_path,
    }
    dogstats_reason = params[:reason] || "unknown"
    auto_directed = params[:auto] == "true"
    redirected_path = paths[dogstats_reason.to_sym]
    GitHub.dogstats.increment("github_mobile_two_factor.navigating_away", tags: ["reason: #{dogstats_reason}", "auto_directed: #{auto_directed}"])
    redirect_to redirected_path
  end

  private

  def two_factor_sms_login_captcha_was_verified?
    return true if !Octocaptcha.new(session, page: :two_factor_sms_login, user: @user).show_captcha?

    octocaptcha = Octocaptcha.new(session, params["octocaptcha-token"], page: :two_factor_sms_login, user: @user)
    octocaptcha.verify
    return true if octocaptcha.solved?

    # if there was an error loading captcha send a metric and report
    if params[:error_loading_captcha]
      GitHub.dogstats.increment("two_factor_sms_login_captcha.error_loading_captcha")
      Failbot.report(
        Octocaptcha::UnableToLoadCaptcha.new,
        "app": "octocaptcha-errors",
        "gh.request_id": GitHub.context[:request_id],
        "user_agent.original": request.user_agent.to_s,
      )
      @octocaptcha_timeout = Octocaptcha::HIGHER_BROWSER_LOAD_TIMEOUT
    end

    false
  end

  # Redirect session.create to SSO login if the login_field is a valid emu handle
  def emu_login?
    business_by_login_shortcode.enterprise_managed_user_and_external_provider_enabled? &&
    !params[:login]&.include?("_#{Business::ManagedUserDependency::ADMIN_SUFFIX}") &&
    !User::EnterpriseManagedDependency::INVALID_UNDERSCORE_LOGIN.include?(params[:login])
  end

  def emu_first_admin_login?
    business_by_login_shortcode&.enterprise_managed_user_enabled? &&
    params[:login] == "#{business_by_login_shortcode.shortcode}_#{Business::ManagedUserDependency::ADMIN_SUFFIX}" &&
    !User::EnterpriseManagedDependency::INVALID_UNDERSCORE_LOGIN.include?(params[:login])
  end

  def emu_login_add_account_for_business?
    # attempting to login to given business
    return false unless emu_login?

    # current_user belongs to business
    return false unless logged_in?
    return false unless current_user.is_enterprise_managed?
    return false unless current_user.enterprise_managed_business == business_by_login_shortcode

    # attempted user is different than current_user
    # note: need to use login instead of display_login b/c login param does include tenant slug
    current_user.login != params[:login] # rubocop:disable GitHub/DoNotAllowLogin
  end

  # Redirects to the business SSO page if
  # 1. proxima login experience is true
  # 2. current_tenant exists
  # 3. an external provider (either SAML or OIDC) is enabled
  def proxima_login_redirect?
    GitHub.proxima_login_experience? &&
    (current_tenant = get_current_tenant) &&
    current_tenant&.external_provider_enabled? &&
    !params[:admin].present?
  end

  # Grabs the first emu admin login and sets it in the login param and in the request login param
  # Only sets it in the Proxima environment and if the proxima_first_emu_admin_login_experience FF is enabled
  def set_first_emu_admin
    return unless GitHub.flipper[:proxima_first_emu_admin_login_experience].enabled?
    return unless GitHub.multi_tenant_enterprise?
    # If we are in development mode and emu_dev_bootstrap FF is enabled, we don't want to override the login param
    return if Rails.env.development? && GitHub.flipper[:emu_dev_bootstrap].enabled? && emu_login?
    # If the login param already exists, we don't want to override it
    return if params[:login].present?

    current_tenant = get_current_tenant
    return unless current_tenant.present?

    first_emu_admin = current_tenant&.find_first_emu_owner&.display_login
    # Set it in the request login param to be able to authenticate the user properly
    request.params[:login] = first_emu_admin
    # Set it in the login param to be able to redirect to the correct page with the emu_first_admin_login? check
    params[:login] = first_emu_admin
  end

  def get_current_tenant
    GitHub::CurrentTenant.get
  end

  # Check if the return_to param will direct back to the user setting page
  def from_settings?
    params[:return_to].present? && params[:return_to] == settings_security_path
  end

  # Record WebAuthn client support stats
  def register_webauthn_client_support(is_success, failure_reason)
    webauthnSupport = if %w[supported unsupported].include? params[:"webauthn-support"]
      params[:"webauthn-support"]
    else
      "unknown"
    end
    webauthnIUVPAASupport = if %w[supported unsupported].include? params[:"webauthn-iuvpaa-support"]
      params[:"webauthn-iuvpaa-support"]
    else
      "unknown"
    end

    GitHub.dogstats.increment("login_webauthn_support", tags: [
      "current-support:#{session[:trusted_device_supported]}",
      "webauthn-support:#{webauthnSupport}",
      "webauthn-iuvpaa-support:#{webauthnIUVPAASupport}",
      "javascript-support:#{params[:"javascript-support"]}",
      "success:#{is_success}",
      "failure_type:#{failure_reason}",
      "confirm:#{params[:confirm]}"
    ])

    session[:trusted_device_supported] = if session[:trusted_device_supported].nil?
      webauthnIUVPAASupport # always set it for the first time
    elsif webauthnIUVPAASupport == "unknown"
      session[:trusted_device_supported] # don't set it to unknown if it's already set
    else
      session[:trusted_device_supported] = webauthnIUVPAASupport # otherwise overwrite with new value
    end
  end

  def anonymous_required_for_login
    # allow logged in users to access the /login page if the
    # :add_account param is present and they are allowed to add an account
    if logged_in? && params[:add_account].presence == "1"
      if account_switcher_helper.can_add_account?
        GitHub.dogstats.increment("account_switcher.add_account_get", tags: ["reason:can_add_account"])
        return
      elsif account_switcher_helper.at_account_maximum? && account_switcher_helper.invalid_account_already_exists?(params[:login])
        GitHub.dogstats.increment("account_switcher.add_account_get", tags: ["reason:invalid_account_exists"])
        return
      end
    end

    # Assumes return_to has been set via the set_return_to before_filter.
    redirect_to_return_to if logged_in?
  end

  def sms_delivery_error_message(message)
    "We tried sending an SMS to your configured number, but #{message}." +
    " Please contact support if you continue to have problems."
  end

  def render_for_incorrect_otp(user, type: nil)
    @user = user
    if type == :sms
      render "sessions/two_factor_sms_prompt"
    elsif type == :app
      render "sessions/two_factor_app_prompt"
    else
      GitHub.dogstats.increment("render_for_incorrect_otp.no_specified_type")
      if user.two_factor_credential&.sms_preferred? && user.two_factor_sms_enabled?
        render "sessions/two_factor_sms_prompt"
      elsif user.two_factor_configured_with?(:app)
        render "sessions/two_factor_app_prompt"
      elsif user.two_factor_sms_enabled?
        render "sessions/two_factor_sms_prompt"
      else
        GitHub.dogstats.increment("two_factor_prompt_no_configured_methods", tags: ["action:login"])
        render_404
      end
    end
  end

  def render_two_factor_prompt_for(user)
    return render_404 unless user

    # check if they prefer sms over app and if they have an sms configured
    if user.two_factor_credential&.sms_preferred? && user.two_factor_sms_enabled?
      return redirect_to two_factor_sms_confirm_path
    end

    # if we've made it this far, we'll show app or sms with app preferred if available
    return redirect_to two_factor_app_prompt_path if user.two_factor_configured_with?(:app)
    if user.two_factor_sms_enabled?
      return redirect_to two_factor_sms_confirm_path
    end

    # this is not an expected state, but instead of 404ing we'll
    # take them to the recovery code prompt to be safest
    GitHub.dogstats.increment("two_factor_prompt_no_configured_methods", tags: ["action:login"])
    redirect_to two_factor_recover_prompt_path
  end

  def render_code_sent(user)
    head :ok
  end

  def render_code_not_sent(user, message)
    render plain: message, status: 422
  end

  def remove_saml_cookies
    cookies.delete(:saml_return_to)
    cookies.delete(:saml_csrf_token)
    cookies.delete(:saml_return_to_legacy)
    cookies.delete(:saml_csrf_token_legacy)
  end

  def set_partially_authenticated_two_factor_session(user)
    session[:two_factor_user] = user.login # rubocop:todo GitHub/DoNotAllowLogin https://github.com/github/authentication/issues/2400
    session[:otp_retry_expires_at] = Time.now.to_i + TwoFactorCredential::OTP_RETRY_WINDOW
  end

  def get_partially_authenticated_two_factor_session
    user_login = session.delete(:two_factor_user)
    otp_retry_expires_at = session.delete(:otp_retry_expires_at)
    otp_retry_allowed = otp_retry_expires_at && Time.now.to_i < otp_retry_expires_at
    [user_login, otp_retry_allowed]
  end

  def should_rate_limit
    return GitHub.flipper[:rate_limit_logins].enabled? if LOGIN_ACTIONS.include?(params[:action])
    true
  end

  def sessions_rate_limit_max
    if SMS_DELIVERY_ACTIONS.include?(params[:action])
      5
    elsif OTP_ENTRY_ACTIONS.include?(params[:action])
      10
    elsif LOGIN_ACTIONS.include?(params[:action])
      return 50 if GitHub.flipper[:rate_limit_logins_strict].enabled?

      if GitHub.flipper[:rate_limit_logins_faster].enabled?
        100
      else
        1000
      end
    end
  end

  def sessions_rate_limit_ttl
    if SMS_DELIVERY_ACTIONS.include?(params[:action])
      60.minutes
    elsif OTP_ENTRY_ACTIONS.include?(params[:action])
      5.minutes
    elsif LOGIN_ACTIONS.include?(params[:action])
      return 2.minutes if GitHub.flipper[:rate_limit_logins_strict].enabled?

      if GitHub.flipper[:rate_limit_logins_faster].enabled?
        10.seconds
      else
        2.minutes
      end
    end
  end

  def sessions_rate_limit_key
    if LOGIN_ACTIONS.include?(params[:action])
      ["session_auth", params[:action], request.remote_ip, sessions_login_rate_limit_key_suffix].compact.join(":")
    else
      ["session_auth", params[:action], authentication_user.id].join(":")
    end
  end

  def sessions_login_rate_limit_key_suffix
    "strict" if GitHub.flipper[:rate_limit_logins_strict].enabled?
  end

  def sessions_glb
    LOGIN_ACTIONS.include?(params[:action])
  end

  def sessions_rate_limit_render
    if LOGIN_ACTIONS.include?(params[:action])
      message = <<~MSG
      You've tried to login too many times.
      Please wait a few minutes and contact support if you continue to have problems.
      MSG
      render plain: message, status: 429
    elsif SMS_DELIVERY_ACTIONS.include?(params[:action])
      # Use GitHub::SMS::RateLimitError to ensure consistent error messages
      error = GitHub::SMS::RateLimitError.new
      message = sms_delivery_error_message(error.message)
      render plain: message, status: 429
    elsif authentication_user
      message = <<~MSG
      We were unable to authenticate your request because too many codes have been submitted.
      Please wait a few minutes and contact support if you continue to have problems.
      MSG
      render plain: message, status: 429
    else
      render plain: "", status: 403
    end
  end

  # Private: Overrides ApplicationController#verify_authenticity_token?
  #
  # Returns true if we're routing from SAML, and the current auth adaptor is
  # SAML. This is because sessions#create is shared by dotcom built-in auth, and
  # GitHub Cloud saml auth.
  def verify_authenticity_token?
    super && request.path != "/saml/consume"
  end

  # Private: convenience method to populate a hash of available 2FA challenges
  # at the time of a challenge, not necessarily the method that was used
  # to solve the challenge.
  def two_factor_delivery_options(user, can_use_u2f, can_use_gh_mobile_2fa)
    delivery_options = {
      app: user.two_factor_configured_with?(:app),
      sms: user.two_factor_configured_with?(:sms),
    }

    if can_use_u2f
      delivery_options[:u2f] = true
    end

    if can_use_gh_mobile_2fa
      delivery_options[:gh_mobile] = true
    end

    if user.two_factor_sms_fallback_enabled?
      delivery_options[:backup_sms_number] = true
    end

    delivery_options
  end

  def authentication_user_required
    redirect_to_login unless authentication_user
  end

  # Private: Log the type of two factor request
  # for the given user.
  #
  # Example:
  #
  #   instrument_two_factor_requested(user: current_user, delivery_options: { totp: "app" })
  #
  # Returns nil.
  def instrument_two_factor_requested(user:, delivery_options:)
    user.instrument_two_factor_requested(
      actor_ip: request.remote_ip,
      note: "From #{request.host}",
      delivery_options: delivery_options,
    )
  end

  def instrument_failed_passkey_login(user:, reason:)
    GlobalInstrumenter.instrument("user.failed_login", {
      actor: user,
      passwordless: true,
    })
    User.instrument_failed_login(
      actor_ip: request.remote_ip,
      note: "From #{request.host}",
      user: user.display_login,
      user_id: user.id,
      actor: user.display_login,
      actor_id: user.id,
      failure_reason: reason,
      failure_type: :passkey,
    )

    if reason == :suspended
      # Despite account being suspended a successful login event should be recorded
      # to hydro for abuse detection.
      GlobalInstrumenter.instrument("user.successful_login", {
        actor: user,
        primary_email: user.primary_user_email,
        elected_to_receive_marketing_email: nil,
        return_to: session[:return_to],
        authentication_record: nil,
        passwordless: true,
      })
    end
  end

  # Private: Log 2fa recovery code use
  def instrument_two_factor_recover(user)
    GitHub.dogstats.increment("two_factor", tags: ["action:recover", "result:success"])
    user.instrument_two_factor_recover(
      actor_ip: request.remote_ip,
      note: "From #{request.host}",
    )
  end

  # Private: Log 2fa successful challenge responses
  def instrument_two_factor_challenge_success(user:, type:, payload: {})
    GitHub.dogstats.increment("two_factor", tags: ["action:challenge", "result:success", "two_factor_type:#{type}"])
    user.instrument_two_factor_challenge_success(
      payload.merge(
        actor_ip: request.remote_ip,
        note: "From #{request.host}",
        two_factor_type: type,
    ))
  end

  # Private: Log 2fa challenge failures
  def instrument_two_factor_challenge_failure(user:, type:)
    GitHub.dogstats.increment("two_factor", tags: ["action:challenge", "result:failure", "two_factor_type:#{type}"])

    user.instrument_two_factor_challenge_failure(
      actor_ip: request.remote_ip,
      note: "From #{request.host}",
      two_factor_type: type,
    )
  end

  def set_current_application
    if client_id = params[:client_id]
      client_id_type = Integration.client_id_type(client_id)
      @application = if client_id_type != :none
        integration = Integration.find_by(key: client_id)

        if client_id_type == :v1
          integration
        elsif integration&.owner&.feature_enabled?(:globally_unique_client_ids)
          integration
        end
      else
        OauthApplication.find_by_key(client_id)
      end
    end

    if @application.nil? && params[:integration]
      @application = Integration.find_by(slug: params[:integration])
    end

    app_id = params[:client_id] || params[:integration]
    GitHub.current_span&.add_attributes({ "gh.request.application.id" => app_id.to_s, "gh.application.id" => @application&.id.to_s, "gh.application.class" => @application&.class&.name.to_s })
  end

  def unset_application_if_spammy
    @application = nil if @application&.spammy?
  end

  def current_device(user)
    user.authenticated_devices.find_by_device_id(current_device_id)
  end

  def redirect_to_passkey_registration_or_return_to(user, prevent_redirect_to_login: false)
    if session[:trusted_device_supported] == "supported" && prompt_for_passkey_registration?(user)
      flash[:stale_session_signedin] = "SIGNED_IN"
      redirect_to trusted_device_registration_prompt_path
    else
      redirect_after_successful_login
    end
  end

  def redirect_after_successful_login(fallback: "/")
    flash[:stale_session_signedin] = "SIGNED_IN"

    if return_to && Addressable::URI.parse(return_to).path == login_path
      # if we've just completed a login request, prevent a redirect to /login. send the user
      # to the homepage instead.
      return redirect_to home_path
    end
    redirect_to_return_to(fallback: fallback)
  end

  def upsell_enabled?(user)
    if GitHub.enterprise? && GitHub.passkeys_enabled?
      return GitHub.enterprise_passkeys_upsell == true
    end

    return false unless user.two_factor_authentication_enabled? && user.passkeys_enabled?
    rand(100) < U2fRegistration::PASSKEY_UPSELL_PERCENTAGE
  end

  def prompt_for_passkey_registration?(user)
    return false unless upsell_enabled?(user)
    # don't bother people that don't want to be bothered
    return false if !!current_device(user)&.declined_passkey_registration?
    # only ask until they have one passkey registered
    return false if user.has_registered_passkey?
    # always prompt at this point
    true
  end

  def two_factor_redirect(user: authentication_user)
    # We require all of the following conditions:
    # - Webauthn is (maybe) supported in the browser. The following values are
    #   possible, and we err on the side of encouraging security keys. We try
    #   WebAuthn unless the client specifically sends `unsupported`. We have a
    #   reasonable fallback flow for when we guess wrong.
    #   - `supported`
    #   - `unsupported`
    #   - `unknown` (fallback value sent by the login page if feature detection
    #   doesn't work / doesn't work fast enough / JS is disabled)
    #   - (nil)
    # - Security keys are enabled for this request in the current server configuration.
    # - The user has at least one security key registered.
    can_use_webauthn = params[:"webauthn-support"] != "unsupported" &&
      request_origin_can_support_webauthn?(request) &&
      user.has_webauthn_credential?

    can_use_gh_mobile_2fa = can_use_gh_mobile_auth?(user)

    instrument_two_factor_requested(user: user, delivery_options: two_factor_delivery_options(user, can_use_webauthn, can_use_gh_mobile_2fa))

    # direct to the user preference if it's set and available
    # if the preference is set and it happens to be unavailable, we'll fall back to GitHub's preference
    if user.two_factor_credential.webauthn_preferred?
      return redirect_to webauthn_prompt_path if can_use_webauthn
    elsif user.two_factor_credential.github_mobile_preferred?
      return redirect_to github_mobile_two_factor_prompt_path if can_use_gh_mobile_2fa
    elsif user.two_factor_credential.app_preferred?
      return redirect_to two_factor_app_prompt_path
    elsif user.two_factor_credential.sms_preferred?
      return redirect_to two_factor_sms_confirm_path
    end

    # otherwise, direct to the first available method based on our (GitHub's) preference
    if can_use_webauthn
      redirect_to webauthn_prompt_path
    elsif can_use_gh_mobile_2fa
      redirect_to github_mobile_two_factor_prompt_path(auto: true)
    elsif user.two_factor_configured_with?(:app)
      redirect_to two_factor_app_prompt_path
    elsif user.two_factor_configured_with?(:sms)
      redirect_to two_factor_sms_confirm_path
    else
      redirect_to two_factor_recover_prompt_path
    end
  end
end
