# typed: true
# frozen_string_literal: true

class TwoFactorRecoveryRequestController < ApplicationController
  include ApplicationController::GitHubMobileAuthDependency
  include GitHub::RateLimitable

  layout "layouts/session_authentication"

  # This controller does not access protected organization resources.
  skip_before_action :perform_conditional_access_checks # rubocop:disable GitHub/DoNotSkipCapBeforeAction
  skip_before_action :require_two_factor_checkup

  before_action :dotcom_required
  before_action :require_valid_user, except: [:abort, :confirm_abort, :continue, :confirm_continue, :without_password]
  before_action :require_current_request, except: [:start, :abort, :confirm_abort, :continue, :confirm_continue, :without_password]
  before_action :require_current_otp, only: [:prompt]

  rate_limit_requests except: :send_otp

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    only: [:prompt]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    only: [:abort]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Authnd,
    only: [:continue]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    only: [:account_recovery_abort_metrics]

  OTP_SEND_LIMIT_OPTIONS = {
    max_tries: 5,
    ttl: 15.minutes,
  }

  # Window of time in which the OTP code is valid.
  ONE_TIME_PASSWORD_EXPIRY = 1.hour

  # string to help parse simple token input mistake
  HELP_MESSAGE = "PleaseprovidethefollowingverificationtokentoGitHubSupport.".freeze

  private def get_recovery_user
    login = session.delete(:two_factor_user)
    return login, :two_factor_user if login

    login = session[:user_without_password]
    if login.present? && User.find_by_login(login).feature_enabled?(:tfa_recovery_without_password)
      session.delete(:user_without_password)
      return login, :user_without_password if login
    end

    [nil, nil]
  end

  private def set_recovery_user(user, type)
    session[type] = user.login # rubocop:todo GitHub/DoNotAllowLogin
  end

  def require_valid_user # rubocop:todo GitHub/UseRestfulActions
    login, type = get_recovery_user
    return render_404 unless login

    @locked_out_user = User.find_by_login(login)
    return render_404 unless @locked_out_user

    return render_404 unless @locked_out_user.two_factor_credential.present?
    @tfa_recovery_without_password = type == :user_without_password

    # get_recovery_user will clear the session value intentionally.
    # re-set the value here, after finishing user validation
    set_recovery_user(@locked_out_user, type)
  end

  def require_current_request # rubocop:todo GitHub/UseRestfulActions
    device = @locked_out_user.authenticated_devices.find_by_device_id(current_device_id)
    return handle_lost_context unless device.present?

    @current_request = TwoFactorRecoveryRequest.find_request(@locked_out_user, device)
    handle_lost_context unless @current_request.present?
  end

  # for users w/o password, force email re-verification if the user has not completed the recovery flow
  # within the allowed time window
  def require_current_otp # rubocop:todo GitHub/UseRestfulActions
    login = session[:user_without_password]
    return unless login.present?

    return if @current_request.review_state == :ready_for_review

    allow_without_password = User.find_by_login(login).feature_enabled?(:tfa_recovery_without_password)
    if !allow_without_password || session[:two_factor_user].present?
      session.delete(:user_without_password)
      session.delete(:otp_expiry_without_password)
      return
    end

    if session[:otp_expiry_without_password].present? && session[:otp_expiry_without_password].to_i < Time.now.to_i
      ActiveRecord::Base.connected_to(role: :writing) do
        @current_request.unverify_otp
      end
      session.delete(:otp_expiry_without_password)
    end
  end

  def existing_otp_present? # rubocop:todo GitHub/UseRestfulActions
    session[:one_time_password].present?
  end

  def existing_otp_not_expired? # rubocop:todo GitHub/UseRestfulActions
    session[:one_time_password_expiration].present? && session[:one_time_password_expiration].to_i >= Time.now.to_i
  end

  def existing_otp_usable? # rubocop:todo GitHub/UseRestfulActions
    existing_otp_present? && existing_otp_not_expired?
  end

  def existing_otp_matches?(otp) # rubocop:todo GitHub/UseRestfulActions
    return false unless existing_otp_usable?

    otp == session[:one_time_password]
  end

  def token_valid_for_recovery?(oauth_access) # rubocop:todo GitHub/UseRestfulActions
    return false unless oauth_access&.personal_access_token?
    return false unless oauth_access.user == @locked_out_user
    return false unless oauth_access.scopes.include? "repo"

    true
  end

  def request_completed # rubocop:todo GitHub/UseRestfulActions
    GlobalInstrumenter.instrument("two_factor_account_recovery.updated",
      action_type: :REQUEST_COMPLETED,
      user: @current_request.user,
      evidence_type: @current_request.hydro_evidence_type,
    )

    GitHub.dogstats.increment("two_factor_account_recovery.request_submitted", tags: [
      "evidence_type:#{@current_request.hydro_evidence_type}",
      "without_password:#{@tfa_recovery_without_password}"
    ])
    @current_request.mark_as_complete!

    send_mailer_to_user
  end

  def start # rubocop:todo GitHub/UseRestfulActions
    current_device = @locked_out_user.authenticated_devices.find_by_device_id(current_device_id)
    request = TwoFactorRecoveryRequest.find_request(@locked_out_user, current_device)

    unless request.present?
      recovery_request = create_and_validate_request(@locked_out_user, current_device)
      return redirect_back fallback_location: login_path if recovery_request.nil?

      clear_otp_state
      set_device_hash(current_device_id)
    end

    redirect_to two_factor_recovery_request_path
  end

  def without_password #rubocop:todo GitHub/UseRestfulActions
    password_reset = PasswordReset.find_by_token params[:reset_token]
    unless password_reset && password_reset.valid?
      return render_404
    end

    reset_user = password_reset.user
    return render_404 unless reset_user.allow_tfa_recovery_without_password?

    set_recovery_user(reset_user, :user_without_password)
    _, current_device = AuthenticatedDevice.find_device_or_create!(
      reset_user,
      device_id: current_device_id,
      display_name: AuthenticatedDevice.generated_display_name(Browser.new(request.user_agent)),
    )

    reset_user.instrument_two_factor_recovery_without_password
    request = TwoFactorRecoveryRequest.find_request(reset_user, current_device)
    request = create_and_validate_request(reset_user, current_device) unless request.present?
    return redirect_back fallback_location: login_path if request.nil?

    # let user coming from pw reset skip OTP verification, since they have verified an OTP during pw reset
    request.verify_otp
    session[:otp_expiry_without_password] = ONE_TIME_PASSWORD_EXPIRY.from_now.to_i

    redirect_to two_factor_recovery_request_path
  end

  private def create_and_validate_request(user, device)
    recovery_request = user.two_factor_recovery_requests.create(requesting_device: device)
    unless recovery_request.valid?
      error_message = recovery_request.errors.to_hash.transform_values(&:to_sentence).map { |key, value| "#{key}: #{value}" }.join(", ")
      entrypoint = @tfa_recovery_without_password ? "without_password" : "partially_authenticated"
      GitHub.logger.error({
        "code.function": "TwoFactorRecoveryRequestController.start",
        "exception.message": error_message,
        "recovery.entrypoint": entrypoint
      })

      flash[:error] = "Recovery process could not be started."
      return nil
    end

    recovery_request
  end

  private def verified_device? # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    return @verified_device if defined?(@verified_device)
    current_device = @locked_out_user.authenticated_devices.find_by_device_id(current_device_id)
    @verified_device = GitHub.sign_in_analysis_enabled? && current_device&.verified?
  end

  private def ssh_keys_available? # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    return @ssh_keys_available if defined?(@ssh_keys_available)
    threshold_for_secondary_evidence = Time.now.utc
    @ssh_keys_available = @locked_out_user.verified_keys.where("verified_at < ?", threshold_for_secondary_evidence).select(&:can_verify_account_ownership?).any?
  end

  private def tokens_available? # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    return @tokens_available if defined?(@tokens_available)
    threshold_for_secondary_evidence = Time.now.utc
    @tokens_available = @locked_out_user.personal_tokens_for_account_recovery(threshold_for_secondary_evidence, limit: nil).any?
  end

  private def available_factors_count
    [verified_device?, ssh_keys_available?, tokens_available?].count(true)
  end

  def prompt # rubocop:todo GitHub/UseRestfulActions
    if @current_request.review_state == :ready_for_review
      return render "sessions/recovery/pending_review"
    end

    if @current_request.review_state == :evidence_missing || @current_request.review_state == :reviewed_by_staff
      return handle_lost_context
    end

    unless @current_request.otp_verified?
      if existing_otp_usable?
        return render "sessions/recovery/enter_otp", locals: { locked_out_user: @locked_out_user, tfa_recovery_without_password: @tfa_recovery_without_password }
      else
        return render "sessions/recovery/send_otp", locals: { locked_out_user: @locked_out_user, tfa_recovery_without_password: @tfa_recovery_without_password }
      end
    end

    tags = [
      "factors_available:#{available_factors_count}",
      "verified_device:#{verified_device?}",
      "ssh_key:#{ssh_keys_available?}",
      "pat:#{tokens_available?}",
    ]
    GitHub.dogstats.increment("two_factor_account_recovery.otp_verified", tags: tags)

    render "sessions/recovery/otp_verified", locals: {
      verified_device: verified_device?,
      ssh_keys_available: ssh_keys_available?,
      tokens_available: tokens_available?,
      recovery_request_id: @current_request.id,
      tfa_recovery_without_password: @tfa_recovery_without_password,
      show_email_unlink: !block_email_unlink,
    }
  end

  def send_otp # rubocop:todo GitHub/UseRestfulActions
    rate_limit_key = "two-factor-recovery:#{@locked_out_user.id}"
    if rate_limit_increment(rate_limit_key, OTP_SEND_LIMIT_OPTIONS).at_limit?
      flash[:error] = "Too many OTP codes requested. Try again later."
      return redirect_to two_factor_recovery_request_path
    end

    one_time_password = TwoFactorRecoveryRequest.generate_one_time_password
    CriticalAccountRecoveryMailer.send_otp(@locked_out_user, one_time_password).deliver_later

    GlobalInstrumenter.instrument("two_factor_account_recovery.updated",
      action_type: :OTP_SENT,
      user: @locked_out_user,
    )

    GitHub.dogstats.increment("two_factor_account_recovery.otp_sent")

    set_otp_state(one_time_password)

    flash[:notice] = "Recovery email sent"

    redirect_to two_factor_recovery_request_path
  end

  def verify_otp # rubocop:todo GitHub/UseRestfulActions
    if AuthenticationLimit.at_any?(two_factor_login: @locked_out_user.login, increment: true, actor_ip: request.remote_ip) # rubocop:todo GitHub/DoNotAllowLogin https://github.com/github/authentication/issues/2400
      flash[:error] = "Too many incorrect OTP attempts. Please try again later."
      return redirect_to two_factor_recovery_request_path
    end

    if existing_otp_matches?(params[:otp])
      @current_request.verify_otp
      GlobalInstrumenter.instrument("two_factor_account_recovery.updated",
        action_type: :OTP_VERIFIED,
        user: @locked_out_user,
      )
      results = "success"
    else
      flash[:error] = "Unable to verify one-time password"
      result = "failed"
    end

    tags = [
      "result:#{result}",
      "factors_available:#{available_factors_count}",
      "verified_device:#{verified_device?}",
      "ssh_key:#{ssh_keys_available?}",
      "pat:#{tokens_available?}",
    ]
    GitHub.dogstats.increment("two_factor_account_recovery.otp_submitted", tags: tags)

    redirect_to two_factor_recovery_request_path
  end

  def verify_device # rubocop:todo GitHub/UseRestfulActions
    hash = get_device_hash
    if hash.present?
      # detect if the user somehow is trying to verify using a different device
      # than what was identified at the start
      unless SecurityUtils.secure_compare(current_device_id, hash)
        GitHub.dogstats.increment("two_factor_account_recovery.verify_device", tags: ["kind:mismatch"])
        return handle_lost_context
      end
    else
      # there's a possibility that the user restarted the flow with an existing
      # request on the same device, and the session value is missing. log this
      # rather than throwing an error because we don't have a value to compare.
      GitHub.dogstats.increment("two_factor_account_recovery.verify_device", tags: ["kind:missing"])
    end

    current_device = @locked_out_user.authenticated_devices.find_by_device_id(current_device_id)

    verified = current_device&.verified?
    GitHub.dogstats.increment("two_factor_account_recovery.verify_device", tags: ["kind:{#{verified ? 'verified' : 'unverified'}}"])
    if verified
      @current_request.authenticated_device = current_device
      request_completed
      flash[:notice] = "Device verified and request submitted!"
    else
      flash[:error] = "Unable to verify current device"
    end

    redirect_to two_factor_recovery_request_path
  end

  def enter_ssh_key # rubocop:todo GitHub/UseRestfulActions
    render "sessions/recovery/enter_ssh_key"
  end

  def verify_ssh_key # rubocop:todo GitHub/UseRestfulActions
    parsed_token = params[:token].gsub(/[[:space:]]+/, "")
    parsed_token = parsed_token.sub(HELP_MESSAGE, "") if parsed_token.include?(HELP_MESSAGE)

    token = GitHub::Authentication::SignedAuthToken.verify(
      token: parsed_token,
      scope: GitHub::SshVerification::SSH_VERIFICATION_TOKEN_SCOPE
    )

    public_key = @locked_out_user.public_keys.find_by_id(token.data["public_key"]) if token.valid?
    is_valid = public_key_valid_for_account_recovery?(public_key)
    GitHub.dogstats.increment("two_factor_account_recovery.verify_ssh_key", tags: ["valid:#{is_valid}"])

    if is_valid
      @current_request.public_key = public_key
      request_completed
      flash[:notice] = "SSH key verified and request submitted!"
      redirect_to two_factor_recovery_request_path
    else
      flash[:error] = "Unable to verify SSH key"
      render "sessions/recovery/enter_ssh_key"
    end
  end

  def enter_token # rubocop:todo GitHub/UseRestfulActions
    render "sessions/recovery/enter_token"
  end

  def verify_token # rubocop:todo GitHub/UseRestfulActions
    oauth_access = OauthAccessTokens.domain.active(params[:token])

    is_valid = token_valid_for_recovery?(oauth_access)
    GitHub.dogstats.increment("two_factor_account_recovery.verify_token", tags: ["valid:#{is_valid}"])

    if is_valid
      @current_request.oauth_access = oauth_access
      request_completed
      flash[:notice] = "Token verified and request submitted!"
      redirect_to two_factor_recovery_request_path
    else
      flash[:error] = "Unable to verify personal access token"
      render "sessions/recovery/enter_token"
    end
  end

  def abort # rubocop:todo GitHub/UseRestfulActions
    request = TwoFactorRecoveryRequest.find_by(id: params[:id])

    return render_404 unless request.present?

    result = TwoFactorRecoveryRequest.verify_abort_token(params[:token])

    return handle_lost_context unless result.valid? && result.user == request.user

    render "sessions/recovery/confirm_abort"
  end

  def confirm_abort # rubocop:todo GitHub/UseRestfulActions
    request = TwoFactorRecoveryRequest.find_by(id: params[:id])

    return render_404 unless request.present?

    result = TwoFactorRecoveryRequest.verify_abort_token(params[:token])

    return handle_lost_context unless result.valid? && result.user == request.user

    user = request.user
    user&.two_factor_recovery_requests&.where(reviewer: nil)&.each do |request|
      request.instrument_abort
      TwoFactorRecoveryRequestCleanupJob.perform_later(request: request)
    end

    flash[:notice] = "Recovery review aborted"
    render "sessions/recovery/aborted"
  end

  def continue # rubocop:todo GitHub/UseRestfulActions
    request = TwoFactorRecoveryRequest.find_by(id: params[:id])

    return render_404 unless request.present?
    result = TwoFactorRecoveryRequest.verify_complete_token(params[:token])

    return handle_lost_context unless result.valid? && result.user == request.user

    return redirect_to two_factor_recovery_request_path unless request.review_state == :reviewed_by_staff

    return render_404 unless request.approved?

    if logged_in? && current_user != request.user
      return render "sessions/recovery/completed", locals: { require_signout: true }
    end

    render "sessions/recovery/completed"
  end

  def confirm_continue # rubocop:todo GitHub/UseRestfulActions
    request = TwoFactorRecoveryRequest.find_by(id: params[:id])

    return render_404 unless request.present? && request.approved?

    result = TwoFactorRecoveryRequest.verify_complete_token(params[:token])

    return handle_lost_context unless result.valid? && result.user == request.user

    if logged_in? && current_user != request.user
      return redirect_to two_factor_recovery_continue_url(params[:id], params[:token])
    end

    user = User.find_by(id: result.user.id)

    begin
      remove_user_from_2fa_required_orgs(user, request)
    rescue DisableUserTwoFactorCredentialsJob::UnexpectedOrgMembershipError
      GitHub.dogstats.increment("two_factor_account_recovery.disable_credentials_failure")
      flash[:error] = "Unable to complete request. Please try again or contact support at #{GitHub.support_link}."
      return redirect_to two_factor_recovery_continue_url(params[:id], params[:token])
    end

    flash[:notice] = "It is recommended to re-enable 2FA on your account and store your recovery codes for future use"

    TwoFactorRecoveryRequestCleanupJob.perform_later(request: request)
    redirect_to settings_security_path
  end

  def unlink_email # rubocop:todo GitHub/UseRestfulActions
    tags = [
      "has_otp_app: #{@locked_out_user.two_factor_configured_with?(:app)}",
      "has_otp_sms: #{@locked_out_user.two_factor_configured_with?(:sms)}",
      "has_backup_sms: #{@locked_out_user.two_factor_sms_fallback_enabled?}",
      "has_security_key:#{@locked_out_user.has_registered_security_key?}",
      "has_github_mobile:#{can_use_gh_mobile_auth?(@locked_out_user)}",
      "has_trusted_device:#{@locked_out_user.has_registered_passkey?}"
    ]

    if block_email_unlink
      flash[:error] = "Email unlink not allowed."
      GitHub.dogstats.increment("two_factor_account_recovery.email_unlink.blocked",
        tags: ["spammy: #{@locked_out_user.spammy?}", "suspended: #{@locked_out_user.suspended?}"])
      return redirect_to two_factor_recovery_request_path
    end

    unless @current_request.otp_verified?
      flash[:error] = "You must first complete email verification."
      GitHub.dogstats.increment("two_factor_account_recovery.email_unlink.initiated", tags: ["otp_verified: false"].concat(tags))
      return redirect_to two_factor_recovery_request_path
    end

    # TODO: two_factor_credential.delivery_method will be changed when the bulwark update is made to allow more types of primary 2FA
    GitHub.dogstats.increment("two_factor_account_recovery.email_unlink.initiated", tags: ["otp_verified: true"].concat(tags))

    email_unlink = EmailUnlink.new(@locked_out_user)
    redirect_to email_unlink_index_path(token: email_unlink.token)
  end

  # since we're recovering 2FA we don't need to check for org enforcement
  # and prompt for setup
  private def two_factor_enforceable
    :no
  end

  # updating two_factor_account_recovery.abort metrics when the user was redirected from the account recovery flow
  def account_recovery_abort_metrics # rubocop:todo GitHub/UseRestfulActions
    redirected_path = get_abort_redirect_path_by_reason(params[:reason])
    GitHub.dogstats.increment("two_factor_account_recovery.abort", tags: ["reason: #{params[:reason]}"])
    redirect_to redirected_path
  end

  private

  def get_abort_redirect_path_by_reason(reason)
    paths = {
      two_factor_recover_prompt: two_factor_recover_prompt_path,
      github_mobile_two_factor_prompt: github_mobile_two_factor_prompt_path,
      password_reset: password_reset_path
    }

    redirected_path = two_factor_recover_prompt_path
    unless reason.blank? || paths[reason.to_sym].blank?
      redirected_path = paths[reason.to_sym]
    end
    redirected_path
  end

  def block_email_unlink
    # Don't offer to unlink emails for risky users if they got here from password reset (without their password)
    @tfa_recovery_without_password && (@locked_out_user.spammy? || @locked_out_user.suspended?)
  end

  def set_device_hash(device_hash)
    return if device_hash.nil?
    session[:recovery_request_device] = device_hash
  end

  def get_device_hash
    session[:recovery_request_device]
  end

  def clear_otp_state
    session.delete(:one_time_password)
    session.delete(:one_time_password_expiration)
  end

  def set_otp_state(otp)
    session[:one_time_password] = otp
    session[:one_time_password_expiration] = ONE_TIME_PASSWORD_EXPIRY.from_now.to_i
  end

  def handle_lost_context(message = "Your 2FA account recovery request was invalid or expired, please try again.")
    flash[:error] = message
    #send them back to the recovery code page, where they can start over from scratch
    redirect_to two_factor_recover_prompt_path
  end

  def user_agent
    # The user-agent is already in the user's session, if they have one;
    # use that to avoid a second parse.
    ua = if user_session && user_session.ua
      user_session.ua
    else
      Browser.new(request.env["HTTP_USER_AGENT"])
    end

    {
      browser: "#{ua.name} #{ua.full_version} #{"(mobile)" if ua.device.mobile?}".strip,
    }
  end

  def public_key_valid_for_account_recovery?(public_key)
    return false unless public_key&.can_verify_account_ownership?

    true
  end

  def remove_user_from_2fa_required_orgs(user, request)
    request.instrument_two_factor_destroy

    GlobalInstrumenter.instrument("two_factor_account_recovery.updated",
      action_type: :TWO_FACTOR_REMOVED,
      user: user,
      evidence_type: request.hydro_evidence_type,
    )

    # disable the user's 2FA credentials, with retries.  we need to instrument the retries here
    # because of the poorly documented interaction between perform_now and retry_on.
    # ref: https://github.com/rails/rails/issues/48281
    1.upto(DisableUserTwoFactorCredentialsJob::MAX_ATTEMPTS) do |attempt|
      final_attempt = attempt == DisableUserTwoFactorCredentialsJob::MAX_ATTEMPTS
      begin
        DisableUserTwoFactorCredentialsJob.perform_now(user.id, report_org_membership_error: final_attempt)
        return
      rescue DisableUserTwoFactorCredentialsJob::UnexpectedOrgMembershipError => error
        if attempt < DisableUserTwoFactorCredentialsJob::MAX_ATTEMPTS
          GitHub.dogstats.increment("two_factor_account_recovery.disable_2fa_credentials_error", tags: ["attempt:#{attempt}"])
        else
          raise error
        end
      end
    end
  end

  def send_mailer_to_user
    abort_token = @current_request.generate_abort_token
    AccountRecoveryMailer.confirm_request_completed(
      @locked_out_user,
      @current_request.id,
      abort_token,
    ).deliver_later
  end
end
