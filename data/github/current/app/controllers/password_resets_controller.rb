# typed: true
# frozen_string_literal: true

class PasswordResetsController < ApplicationController
  include GitHub::RateLimitable
  include ApplicationController::GitHubMobileAuthDependency
  include WebauthnHelper

  layout "layouts/session_authentication"
  javascript_bundle :sessions
  # the signup bundle is required for captcha
  javascript_bundle :signup

  # don't require 2FA checkup for password reset actions
  skip_before_action :require_two_factor_checkup
  skip_before_action :account_2fa_requirement_interrupt

  # The following actions *don't* access protected organization resources
  # so they don't require conditional access checks.
  # rubocop:disable GitHub/DoNotSkipCapBeforeAction
  skip_before_action :perform_conditional_access_checks, only: %w(
    new
    create
    edit
    check_otp
    fallback
    update
    mobile
    mobile_status
  )

  before_action :load_reset, only: [:edit, :update, :check_otp, :fallback, :mobile, :mobile_status]
  before_action :sanitize_analytics_location, :sanitize_hydro_location,
    only: [:edit, :update, :check_otp, :fallback, :mobile, :mobile_status]
  before_action :no_external_auth
  before_action :add_csp_exceptions, only: [:new, :create]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Authnd,
    ApplicationRecord::IamAbilities,
    only: [:edit]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Authnd,
    ApplicationRecord::NotificationsEntries,
    only: [:mobile]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql5,
    ApplicationRecord::NotificationsEntries,
    only: [:new]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:new],
    optional: true

  CSP_EXCEPTIONS = {
    frame_src: [GitHub.urls.octocaptcha_host_name],
  }

  def new
    @failed_auth_email = session[:failed_auth_email]
    if params[:email]
      @requested_reset_user = User.find_by_email(params[:email])
    end
    render "password_resets/new"
  end

  def create
    email = params[:email]
    # If the business slug is present, we need to check if the email (+shortocde) matches first emu admin email for the business
    if GitHub.flipper[:resend_initial_first_emu_admin_password_reset].enabled? && params[:slug].present?
      if (updated_email = email_belongs_to_first_emu_admin?(email: email, slug: params[:slug])).present?
        email = updated_email
      else
        flash.now[:error] = PasswordReset::INVALID_EMAIL_OR_ACCOUNT_TYPE_MESSAGE
        return render "password_resets/new"
      end
    end

    if !GitHub.enterprise? && !password_reset_verified_by_captcha?(email)
      flash[:error] = "Unable to verify your captcha response. " \
      "Please visit #{octocaptcha_help_url} for troubleshooting information."
      return render "password_resets/new"
    end

    # only check/bump the rate limits if the user has successfully completed the captcha (if required)
    if password_reset_rate_limited?
      flash[:error] = "Too many attempts. Please wait a while and try again."
      return render "password_resets/new"
    end

    reset = PasswordReset.create email: email, disallow_hard_bounce: true, current_device_id: current_device_id
    GitHub.context.push(spamurai_form_signals: spamurai_form_signals)
    GlobalInstrumenter.instrument(
      "user.password_reset_create",
      {
        actor: current_user,
        account: reset.user,
        error_type: reset.error,
        email_address: params[:email],
      },
    )

    if !reset.valid?
      GitHub.dogstats.increment("password_reset", tags: ["action:create", "valid:false", "error:#{reset.error}"])
      if reset.user&.suspended?
        return redirect_to suspended_url
      else
        flash.now[:error] = reset.error_message
        return render "password_resets/new"
      end
    end

    GitHub.dogstats.increment("password_reset", tags: ["action:create", "valid:true", "verified_email:#{reset.verified_email?}", "current_device_verified:#{reset.verified_device?}"])
    render "password_resets/create"
  end

  # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
  def authentication_user # rubocop:todo GitHub/UseRestfulActions
    return @authentication_user if defined? @authentication_user

    # When someone is visiting the password reset page, we need to make sure the
    # authentication user we use is the one who is resetting their password, not
    # the one who is (maybe) logged in. That value is `@user` when set by `edit`
    # in the relevant code path.
    if defined? @user
      @authentication_user = @user
      return @user
    end

    # Fall back to the current user by default.
    @authentication_user = current_user
    @authentication_user
  end
  # rubocop:enable GitHub/ControllersShouldUseMemoizeForMemoization

  SMS_RESEND_LIMIT_OPTIONS = {
    max_tries: 5,
    ttl: 15.minutes,
  }

  # this is a GET request which is used to generate a GitHub Mobile 2fa Password Reset challenge
  # and display a prompt to the user
  def mobile # rubocop:todo GitHub/UseRestfulActions
    auto_directed = params[:auto] == "true"
    if AuthenticationLimit.at_any?(two_factor_login: @reset.user.login, actor_ip: request.remote_ip) # rubocop:disable GitHub/DoNotAllowLogin used in a query
      flash[:error] = "Two factor authentication cannot be used at this time. Please try again later."
      return redirect_to edit_password_reset_path(@reset.token)
    end

    if mobile_status_successful?
      return redirect_to edit_password_reset_path(@reset.token)
    end

    return redirect_to edit_password_reset_path unless password_reset_github_mobile_available?

    GitHub.dogstats.increment("github_mobile_two_factor_password_reset", tags: ["action: navigated_to"])

    skip_challenge = false
    success = initiate_mobile_auth_request(:two_factor_password_reset, @reset.user, skip_challenge, auto_directed)
    # If authnd cannot be reached, fall back to the totp/webauthn 2fa page
    if !success
      GitHub.dogstats.increment("github_mobile_two_factor_password_reset", tags: ["action: failed_authnd_initiate_request"])
      return redirect_to edit_password_reset_path(auto: "true", from: "mobile_2fa_password_reset")
    end

    if @reset.forced_weak_password_reset?
      flash.now[:error] = @reset.weak_password_reset_message
    end

    @user = @reset.user

    render "password_resets/mobile", locals: {
      challenge: session[:gh_mobile_challenge],
      user: @user,
      token: @reset.token,
    }
  end

  def mobile_status # rubocop:todo GitHub/UseRestfulActions
    # must be an XHR request
    return render_404 unless request.xhr?

    @user = @reset.user

    result = get_mobile_auth_request_status(:two_factor_password_reset, @user)
    # return early if we cleared out a stale auth request
    return render json: { status: result }, status: :internal_server_error if result == :STATUS_ERROR

    case result
    when :STATUS_APPROVED
      instrument_two_factor_success("github_mobile")
      @reset.verify_github_mobile_2fa
    when :STATUS_REJECTED
      flash[:error] = "GitHub Mobile authentication failed."
      GitHub.dogstats.increment("two_factor_password_reset", tags: ["action:challenge", "result:failure", "two_factor_type:github_mobile"])
      if AuthenticationLimit.at_any?(two_factor_login: @user.login, increment: true, actor_ip: request.remote_ip) # rubocop:disable GitHub/DoNotAllowLogin used in a query
        flash[:error] = "Two factor authentication cannot be used at this time. Please try again later."
      end
    when :STATUS_EXPIRED
      GitHub.dogstats.increment("two_factor_password_reset", tags: ["action:challenge", "result:expired", "two_factor_type:github_mobile"])
    end

    # if we've made it this far, it's safe to return the status from authnd to the client
    render json: { status: result, token: @reset.token }
  end

  def edit
    flash.now[:override_octolytics_location] = true
    auto_directed = params[:auto] == "true"
    if @reset.forced_weak_password_reset?
      flash.now[:error] = @reset.weak_password_reset_message
    end

    @user = @reset.user

    # if they can use mobile auth and aren't auto-redirected here from a #mobile failure
    if password_reset_github_mobile_available? && auto_directed && !params[:from] && !params[:totp_type]
      # Only redirect to GitHub Mobile prompt if:
      #    - the user has it set to their preferred method or
      #    - webauthn is their preferred method and webauthn is not available or
      #    - the user has not set a preference and webauthn is not available
      # all other cases should fall through to the regular password reset page which shows both totp and webauthn options by default
      two_factor_credential = @user.two_factor_credential
      return redirect_to edit_password_reset_mobile_path(auto: "true") if two_factor_credential&.github_mobile_preferred? || ((two_factor_credential&.webauthn_preferred? || two_factor_credential&.login_preference.nil?) && !password_reset_webauthn_available?)
    end

    if params[:from] == "mobile_2fa_password_reset"
      GitHub.dogstats.increment("github_mobile_two_factor.navigating_away", tags: ["reason: two_factor_password_mobile", "auto_directed: #{auto_directed}"])
    end

    send_sms = params.has_key?(:send_sms) ? params[:send_sms] == "true" : true
    resending_sms = params.has_key?(:resending_sms) ? params[:resending_sms] == "true" : false

    render_password_resets_edit(@user, totp_type: params[:totp_type], send_sms: send_sms || resending_sms, resending_sms: resending_sms)
  end

  def check_otp # rubocop:todo GitHub/UseRestfulActions
    webauthn_response = params[:webauthn_response]
    challenge, _ = webauthn_sign_challenge_from_request(@reset.user)
    unless webauthn_response.blank? || challenge.blank?
      origin = Addressable::URI.new(scheme: request.scheme, host: request.host).to_s
      unless @reset.verify_u2f(origin, challenge, webauthn_response)
        flash[:error] = "Authentication failed"
      end
      instrument_two_factor_success("webauthn")
      return redirect_to edit_password_reset_path(@reset.token)
    end

    otp, active_totp_type = GitHub::TwoFactorAuthentication.normalize_otp_from_params(params, action: "password_reset")

    instrumented_type = GitHub::TwoFactorAuthentication.recovery_code?(otp) ? "recovery_code" : active_totp_type&.to_s

    if AuthenticationLimit.at_any?(two_factor_login: @reset.user.login, increment: true, actor_ip: request.remote_ip) # rubocop:disable GitHub/DoNotAllowLogin used in a query
      flash[:error] = "Two factor authentication cannot be used at this time. Please try again later."
      return render_invalid_otp(instrumented_totp_type: instrumented_type, active_totp_type: active_totp_type)
    elsif !@reset.verify_two_factor(otp, totp_type: active_totp_type)
      reuse = @reset.user.reused_valid_totp?(otp, type: active_totp_type)
      flash[:error] = reuse ? "The two-factor code you entered has already been used or is too old to be used." : "Invalid two-factor code"
      return render_invalid_otp(instrumented_totp_type: instrumented_type, active_totp_type: active_totp_type)
    end

    # since a user can enter a authentication/recovery code in the same box
    # we need to double check if it was a recovery code or not
    instrument_two_factor_success(instrumented_type)

    redirect_to edit_password_reset_path(@reset.token, totp_type: active_totp_type)
  end

  # Send OTP SMS to fallback number.
  def fallback # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless request.xhr?

    unless @reset.user.two_factor_authentication_enabled? && @reset.user.two_factor_sms_fallback_enabled?
      return head :forbidden
    end

    # because this does not reload the page, retrieve error message manually instead of setting flash
    error = try_send_sms(@reset.user.id, fallback: true, error_as_flash: false)
    return head :ok if error.nil?
    render body: error, status: :unprocessable_entity
  end

  def update
    GitHub.context.push(spamurai_form_signals: spamurai_form_signals)
    # save off current_device to variable before a new AuthenticatedDevice is created in the PasswordReset#apply
    current_device = AuthenticatedDevice.where(device_id: current_device_id, user: @reset.user).first
    current_device_verified = !!current_device&.verified?
    current_primary_email = @reset.user.primary_user_email
    other_emails = @reset.user.emails.notifiable - [@reset.user.primary_user_email, @reset.user.backup_user_email]
    if @reset.apply(password: params[:password], password_confirmation: params[:password_confirmation], from_device_id: current_device_id, parsed_useragent: parsed_useragent)
      anonymous_flash[:notice] = "New password set successfully."
      if forgot_password_email = @reset.user.emails.find_by_email(@reset.email)
        GitHub.dogstats.increment("password_reset", tags: [
          "action:update",
          "valid:true",
          "forced_reset:#{@reset.forced_weak_password_reset?}",
          "verified_email:#{forgot_password_email.verified?}",
          "primary:#{current_primary_email.email&.downcase == forgot_password_email.email.downcase}",
          "primary_email_verified:#{!!@reset.user.primary_user_email&.verified?}",
          "backup_email_exists:#{!!@reset.user.backup_user_email}",
          "backup:#{@reset.user.backup_user_email&.email&.downcase == forgot_password_email.email.downcase}",
          "backup_email_verified:#{!!@reset.user.backup_user_email&.verified?}",
          "any_other_emails_verified:#{other_emails.any?(&:verified?)}",
          "authenticated_device_exists:#{!!current_device}",
          "current_device_verified:#{current_device_verified}"
        ])

        if GitHub.email_verification_enabled? && forgot_password_email.unverified?
          forgot_password_email.verify!
        end
      end

      if @reset.user.is_first_emu_owner? && !GitHub.multi_tenant_enterprise?
        redirect_to login_path(login: @reset.user.display_login, return_to: enterprise_getting_started_path(@reset.user.enterprise_managed_business))
      else
        redirect_to_login
      end
    else
      @user = @reset.user

      GitHub.dogstats.increment("password_reset", tags: [
        "action:update",
        "valid:false",
        "weak_password:#{@user.provided_weak_password?}",
      ])

      if @user.provided_weak_password?
        flash.now[::CompromisedPassword::WEAK_PASSWORD_KEY] = true
      else
        flash.now[:error] = @reset.error_message
      end
      render_password_resets_edit(@user)
    end
  end

  # Can the user use U2F instead of traditional 2FA?
  #
  # Returns boolean.
  def password_reset_webauthn_available? # rubocop:todo GitHub/UseRestfulActions
    request_origin_can_support_webauthn?(request) && @reset.user.has_webauthn_credential?
  end
  helper_method :password_reset_webauthn_available?

  private


  def render_password_resets_edit(user, totp_type: nil, send_sms: true, resending_sms: false)
    # if we no longer need two factor, just render the edit page without a specified totp_type
    # at this point the user is able to enter a new password
    return render "password_resets/edit" unless @reset.verify_two_factor?
    return render_404 if !totp_type.blank? && !%w[app sms].include?(totp_type)

    if totp_type == "sms"
      return render_404 unless user.two_factor_sms_enabled?
      try_send_sms(user.id, resending: resending_sms) if send_sms
      return render "password_resets/edit", locals: { totp_type: :sms, allow_tfa_recovery_without_password: user.allow_tfa_recovery_without_password? }
    elsif totp_type == "app"
      return render_404 unless user.two_factor_configured_with?(:app)
      return render "password_resets/edit", locals: { totp_type: :app, allow_tfa_recovery_without_password: user.allow_tfa_recovery_without_password? }
    end

    # use SMS if it's available and it's the only option or the user has explicitly preferred it
    if user.two_factor_sms_enabled? && (!user.two_factor_configured_with?(:app) || user.two_factor_credential&.sms_preferred?)
      try_send_sms(user.id, resending: resending_sms) if send_sms
      return render "password_resets/edit", locals: { totp_type: :sms, allow_tfa_recovery_without_password: user.allow_tfa_recovery_without_password? }
    end

    # if we don't have a specific reason to use SMS (or can't), use app
    render "password_resets/edit", locals: { totp_type: :app, allow_tfa_recovery_without_password: user.allow_tfa_recovery_without_password? }
  end

  # error_as_flash: if true, errors will be set as flash[:error], otherwise they will be returned as a string
  # this is useful because not all callers reload the page, so setting the flash would not have an effect and they need the error beforehand
  def try_send_sms(user_id, fallback: false, error_as_flash: true, resending: false)
    error_message = nil

    password_reset_sms_rate_limit_key = "password-reset-sms-2fa:#{user_id}"
    sms_rate_limit_key = "2fa-sms:#{user_id}"

    known_rate_limited = rate_limit_increment(password_reset_sms_rate_limit_key, SMS_RESEND_LIMIT_OPTIONS).at_limit? ||
      rate_limit_increment(sms_rate_limit_key, SMS_RESEND_LIMIT_OPTIONS).at_limit?
    if known_rate_limited
      error_message = GitHub::SMS::RateLimitError.new.message
    end

    begin
      if fallback
        @reset.user.send_two_factor_fallback_sms(:reset)
      else
        @reset.user.send_two_factor_sms(use_alternate_provider = resending, callsite: :password_reset)
      end
    rescue GitHub::SMS::Error => e
      error_message = e.message
    end unless known_rate_limited

    consumable_error = "We tried sending an SMS to your configured number, but #{error_message}." +
    " Please contact support if you continue to have problems."
    if error_as_flash
      flash[:error] = consumable_error unless error_message.nil?
    else
      consumable_error unless error_message.nil?
    end
  end

  def password_reset_verified_by_captcha?(email)
    user = User.find_by_email(email)
    return true if !Octocaptcha.new(session, page: :password_reset, user: user).show_captcha?

    octocaptcha = Octocaptcha.new(session, params["octocaptcha-token"], page: :password_reset)
    octocaptcha.verify
    return true if octocaptcha.solved?

    # if there was an error loading captcha send a metric and report
    if params[:error_loading_captcha]
      GitHub.dogstats.increment("password_resets_captcha.error_loading_captcha")
      Failbot.report(
        Octocaptcha::UnableToLoadCaptcha.new,
        "app": "octocaptcha-errors",
        "gh.request_id": GitHub.context[:request_id],
        "user_agent.original": request.user_agent.to_s,
      )
      @octocaptcha_timeout = Octocaptcha::HIGHER_BROWSER_LOAD_TIMEOUT
    end

    GitHub.dogstats.increment("password_reset", tags: ["action:create", "valid:false", "error:captcha_not_solved"])
    false
  end

  def password_reset_rate_limited?
    user = User.find_by_email(params[:email])
    if user && AuthenticationLimit.at_any?(increment: true, password_reset_login: user.login) # rubocop:disable GitHub/DoNotAllowLogin used in a query
      GitHub.dogstats.increment("password_reset", tags: ["action:create", "valid:false", "error:rate_limited"])
      return true
    end
    false
  end

  # Can the user use GitHub Mobile instead of traditional 2FA?
  #
  # Returns boolean.
  def password_reset_github_mobile_available?
    @reset.verify_two_factor? && can_use_gh_mobile_auth?(@reset.user)
  end

  # Private: Load and validate the password reset token.
  #
  # Sets @reset or redirects to the "new" action if there is an error.
  def load_reset
    @reset = PasswordReset.find_by_token params[:token]
    unless @reset && @reset.valid?
      flash[:error] = "It looks like you clicked on an invalid password reset link. Please try again."
      redirect_to action: :new
    end
  end

  # if the redirect query param is present and the polling was successful,
  # redirect the user to the proper password reset page as we now have a new SAT token
  def mobile_status_successful?
    params[:redirect].present? && !@reset.verify_two_factor?
  end

  def email_belongs_to_first_emu_admin?(email: nil, slug: nil)
    return nil if GitHub.enterprise?
    return nil unless GitHub.flipper[:resend_initial_first_emu_admin_password_reset].enabled?
    return nil unless email.present? && slug.present?

    business = Business.find_by(slug: params[:slug])
    return nil unless business.present?
    return nil unless business.enterprise_managed_user_enabled?

    current_first_emu_admin_email = business.find_first_emu_owner.email
    comparsion_first_emu_admin_email = business.add_emu_shortcode_to_emails(params[:email], first_enterprise_owner: true)
    return nil if current_first_emu_admin_email != comparsion_first_emu_admin_email

    comparsion_first_emu_admin_email
  end

  # Private: Log 2fa password reset successful responses
  def instrument_two_factor_success(type)
    GitHub.dogstats.increment("two_factor_password_reset", tags: ["action:challenge", "result:success", "two_factor_type:#{type}"])
  end

  # Private: Log 2fa password reset failure responses and renders the password reset page
  # `instrumented_totp_type` is used to log the two_factor_type in dogstats
  # `active_totp_type` is used to render the edit page with the specific totp type: app or sms
  def render_invalid_otp(instrumented_totp_type: nil, active_totp_type: nil)
    GitHub.dogstats.increment("two_factor_password_reset", tags: ["action:challenge", "result:failure", "two_factor_type:#{instrumented_totp_type}"])
    redirect_to edit_password_reset_path(@reset.token, totp_type: active_totp_type, send_sms: false)
  end

  # Provide a helpful message if a user hits this and the instance is using
  # external auth (without a fallback to built-in auth).
  def no_external_auth
    return if GitHub.auth.allow_builtin_users?
    flash[:error] = "You cannot reset your password because GitHub Enterprise is using an external authentication provider"
    redirect_to "/"
  end

  def sanitize_analytics_location
    override_analytics_location "/password_reset/<password-reset-token>"
  end

  def sanitize_hydro_location
    if hydro_context[:enabled]
      hydro_context.merge!(path: "/password_reset/:token")
    end
  end
end
