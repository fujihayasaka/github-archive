# typed: true
# frozen_string_literal: true

class TwoFactorController < ApplicationController
  include ApplicationHelper
  include TwoFactorHelper
  include SmsRateLimitHelper
  include ApplicationController::TwoFactorHolidayWarningDependency

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Authnd,
    ApplicationRecord::Repositories,
    ApplicationRecord::Configurations,
    only: [:intro]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:intro],
    optional: true

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Authnd,
    ApplicationRecord::Collab,
    only: [:holiday_warning_banner]

  # All actions that are invalid unless a user already has 2FA setup.
  TWO_FACTOR_ENABLED_ACTIONS = %w(two_factor_authentication_disable
                                  add_two_factor_sms_backup
                                  destroy_two_factor_sms_backup
                                  dismiss_holiday_warning_banner
                                )

  TWO_FACTOR_SMS_ACTIONS = %w(
    add_two_factor_sms_backup
    destroy_two_factor_sms_backup
  )

  RECONFIGURABLE_FACTORS = %w(app sms).freeze

  CSP_EXCEPTIONS = {
    frame_src: [GitHub.urls.octocaptcha_host_name],
  }

  skip_before_action :account_2fa_requirement_interrupt, only: [:intro]
  skip_before_action :require_two_factor_checkup
  before_action :login_required
  before_action :filter_enterprise_managed_users, except: [:holiday_warning_banner]
  before_action :ensure_two_factor_disabled, only: %w(intro recovery_download enable)
  before_action :filter_external_identity_users
  before_action :ensure_user_has_pending_two_factor_setup, only: %w(send_two_factor_sms verify recovery_download enable)
  before_action :validate_type_param, only: %w(initiate verify enable)

  include GitHub::RateLimitedRequest
  rate_limit_requests \
    only: [:send_two_factor_sms, :add_two_factor_sms_backup],
    key: :sms_rate_limit_key,
    log_key: "2fa-sms",
    max: 5,
    ttl: 1.hour,
    at_limit: :render_sms_rate_limit

  before_action :ensure_two_factor_enabled
  before_action :ensure_user_has_two_factor_enabled, only: TWO_FACTOR_ENABLED_ACTIONS
  before_action :sudo_filter, except: [:holiday_warning_banner, :dismiss_holiday_warning_banner, :set_login_2fa_preference]
  before_action :ensure_two_factor_sms_enabled, only: TWO_FACTOR_SMS_ACTIONS
  before_action :add_csp_exceptions, only: [:intro]
  before_action :require_two_factor_holiday_warning, only: [:holiday_warning_banner]

  after_action :instrument_api_stats, only: %w(intro initiate send_two_factor_sms verify recovery_download enable)

  javascript_bundle :"two-factor-setup"
  javascript_bundle :settings
  javascript_bundle :sessions
  # the signup bundle is required for captcha
  javascript_bundle :signup
  stylesheet_bundle :settings

  private def target_for_conditional_access
    return :no_target_for_conditional_access unless logged_in? # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    current_user
  end

  private def filter_external_identity_users
    render_404 unless GitHub.auth.two_factor_authentication_allowed?(current_user)
  end

  private def validate_type_param
    render status: 400, json: { error: "Invalid type" } if params[:type].blank? || !(params[:type] == "sms" || params[:type] == "app")
  end

  # 2FA users shouldn't be using the setup flow, this redirects them back to the authentication settings page where they can inline reconfigure
  def ensure_two_factor_disabled # rubocop:todo GitHub/UseRestfulActions
    return unless current_user.two_factor_authentication_enabled?
    flash[:notice] = "Two-factor authentication is already enabled, You can manage your configuration from this page."
    redirect_to settings_security_path
  end

  def ensure_user_has_pending_two_factor_setup # rubocop:todo GitHub/UseRestfulActions
    unless TwoFactorSetup.pending?(current_user)
      render status: 422, json: { error: "No two-factor setup found. Please cancel and attempt setup again." }
    end
  end

  # Starting the 2FA setup flow by rendering the single page wizard
  def intro # rubocop:todo GitHub/UseRestfulActions
    # Let's remember where the user came from in case the 2FA setup flow was enabled when attempting to accept an org invite
    if referring_params[:controller] == "orgs/invitations"
      return_to = request.referrer
    elsif params[:return_to].present?
      return_to = params[:return_to]
    elsif current_user.is_flagged_for_two_factor_checkup?
      return_to = session[:return_to]
    end

    # Instrument a log to indicate the user is starting the 2FA setup flow
    GitHub.instrument("two_factor_authentication_setup.start", user: current_user)

    render "settings/user/two_factor_setup/index", locals: {
      return_to: sanitize_url(return_to),
      affiliation_disallows_sms_2fa: current_user.affiliation_disallows_sms_2fa?
    }
  end

  # Initiates the 2FA setup flow by creating a temporary 2FA credential
  def initiate # rubocop:todo GitHub/UseRestfulActions
    case params[:type]
    when "sms"
      two_factor_type = :sms
      return render(status: 400, json: { error: "Two-factor SMS not enabled" }) unless GitHub.two_factor_sms_enabled?
    when "app"
      two_factor_type = :app
    end

    # start a two factor setup process. any temporary credentials from pending/cancelled attempts are cleared.
    TwoFactorSetup.start(current_user)
    secret, app_salt_version, recovery_secret, recovery_salt_version = TwoFactorSetup.values_for(current_user, :secret, :app_salt_version, :recovery_secret, :recovery_salt_version)
    response = {
      formatted_recovery_codes: GitHub::TwoFactorAuthentication.formatted_recovery_codes(recovery_secret, recovery_salt_version)
    }

    return render status: 500, json: { error: "Failed to start two-factor setup. Please try again." } unless secret && recovery_secret
    response[:dev_otp] = GitHub::TwoFactorAuthentication.totp(two_factor_type, secret, two_factor_type == :app ? app_salt_version : nil).now if Rails.env.development?

    if two_factor_type == :app
      response[:mashed_secret] = GitHub::TwoFactorAuthentication.mashed_secret(two_factor_type, secret, app_salt_version)
      qr_code = qr_code_generator GitHub::TwoFactorAuthentication.provisioning_url_for_authenticator_app(secret, app_salt_version, current_user.login) # rubocop:todo GitHub/DoNotAllowLogin https://github.com/github/authentication/issues/2400
      response[:qr_code_img_data] = "data:image/svg+xml;base64,#{Base64.encode64(qr_code.as_svg(fill: "FFF", color: "000", module_size: 3)).gsub("\n", "")}"
    end
    render json: response.to_json
  end

  # Sends the user a confirmation SMS during setup
  def send_two_factor_sms # rubocop:todo GitHub/UseRestfulActions
    return render(status: 400, json: { error: "Two-factor SMS not enabled" }) unless GitHub.two_factor_sms_enabled?

    number = GitHub::Messaging.normalize_number(params[:number])
    raise GitHub::Messaging::NumberNotValidError unless GitHub::Messaging.valid_country?(number)
    raise GitHub::Messaging::NumberNotValidError unless GitHub::Messaging.valid_number?(number, use_phonelib: true)

    inline_configure = params[:inline_configure] == "true"
    callsite = inline_configure ? :two_factor_setup_inline : :two_factor_setup_wizard

    blocked, _ = current_user.two_factor_sms_blocked?(sms_number: number, callsite: callsite)
    raise GitHub::Messaging::UnauthorizedRecipientError.new if blocked

    if inline_configure
      current_number = current_user&.two_factor_sms_number
      return render(status: 422, json: { error: "The phone number you entered is the same as your current configuration. Please enter a new phone number." }) if current_number == number

      fallback_number = current_user&.two_factor_backup_sms_number
      return render(status: 422, json: { error: "The phone number you entered is the same as your current fallback number. Remove your fallback and try again." }) if number == fallback_number
    end

    unless send_sms_verified_by_captcha?
      return render(status: 400, json: { error: "Unable to verify your captcha response. " \
        "Please visit the following url for troubleshooting information: #{octocaptcha_help_url}" })
    end

    rate_limited, err_msg = is_send_two_factor_sms_authentication_rate_limited(number)
    return render(status: 429, json: { error: err_msg }) if rate_limited

    secret, last_provider = TwoFactorSetup.values_for(current_user, :secret, :provider)
    otp = GitHub::TwoFactorAuthentication.totp(:sms, secret, nil).now
    message = otp +
      " is your #{GitHub.flavor} authentication setup code."
    message = add_origin_bound_sms_footer(message, otp)

    # Selects provider by special cases(s) or alternates between providers on retry
    provider = GitHub::Messaging.provider_for(number, known_provider: nil, last_used_provider: last_provider, attempt_alternate: !!last_provider)

    # We will save the number provided before they enter the validation code to
    # ensure we save the number to the DB that we actually sent the code to.
    TwoFactorSetup.set_sms_values(current_user, number, provider.provider_name)

    sms_payload = {
      user: current_user,
      provider: provider.provider_name.to_s
    }
    receipt = GitHub::Messaging.send_message(number, message, current_user, provider: provider, reason: callsite, completed_captcha: true)
    sms_payload[:message_id] = receipt.message_id if receipt.present?
    instrument_sms_sent(sms_payload, number, callsite)
    head :ok
  rescue GitHub::Messaging::Error => e
    render_sms_error 422, e.message
  end

  # Verifies otp code received via SMS or app
  def verify # rubocop:todo GitHub/UseRestfulActions
    two_factor_type = params[:type]
    if TwoFactorSetup.verify_totp(two_factor_type.to_sym, current_user, params[:otp])
      GitHub.instrument("two_factor_authentication_setup.verify_success", {
        user: current_user,
        two_factor_type: two_factor_type
      })
      head :ok
    else
      render status: 400, json: { error: "Two-factor code verification failed. Please try again." }
    end
  end

  # Sends a txt file down to the client including the recovery codes
  def recovery_download # rubocop:todo GitHub/UseRestfulActions
    recovery_secret, recovery_salt_version = TwoFactorSetup.values_for(current_user, :recovery_secret, :recovery_salt_version)
    codes = GitHub::TwoFactorAuthentication.formatted_recovery_codes(recovery_secret, recovery_salt_version)
    current_user.instrument_two_factor_recovery_codes_downloaded
    TwoFactorSetup.set_recovery_codes_last_downloaded_at(current_user)
    send_data(
      codes.join("\r\n"),
      filename: "github-recovery-codes.txt",
    )
  end

  # Persists 2FA credential and begins enforcing 2FA
  def enable # rubocop:todo GitHub/UseRestfulActions
    two_factor_type = params[:type]
    return render status: 400, json: { error: "Two-factor SMS not enabled" } if two_factor_type == "sms" && !GitHub.two_factor_sms_enabled?
    return render status: 400, json: { error: "Two-factor authentication not verified" } unless TwoFactorSetup.values_for(current_user, :verified).first
    return render status: 400, json: { error: "Recovery codes must be downloaded" } unless  TwoFactorSetup.values_for(current_user, :recovery_codes_last_downloaded_at).first

    if TwoFactorSetup.enable_two_factor(current_user, two_factor_type)
      clear_account_2fa_requirement_banner_values
      clear_two_factor_checkup_value
      head :ok
    else
      render status: 500, json: { error: "Enabling two-factor authentication failed." }
    end
  end

  # Disable the user's two_factor_credential
  def two_factor_authentication_disable # rubocop:todo GitHub/UseRestfulActions
    if current_user.two_factor_auth_can_be_disabled?
      current_user.two_factor_credential.destroy
      AccountMailer.two_factor_disable(current_user).deliver_later
      GitHub.dogstats.increment("two_factor.disable")
      flash[:notice] = "Two-factor authentication successfully disabled."
      clear_account_2fa_requirement_banner_values
      redirect_to settings_security_path
    else
      redirect_to settings_user_two_factor_authentication_configuration_path
    end
  end

  def two_factor_authentication_configure_factor # rubocop:todo GitHub/UseRestfulActions
    factor = params["type"].to_s
    return render_404 unless factor
    return render_404 unless RECONFIGURABLE_FACTORS.include?(factor)

    if factor == "sms"
      sms_2fa_not_enabled = !GitHub.two_factor_sms_enabled?
      sms_2fa_not_permitted_for_user = !current_user.two_factor_sms_permitted?

      if sms_2fa_not_enabled || sms_2fa_not_permitted_for_user
        GitHub.dogstats.increment("two_factor.reconfigure_factor", tags: ["factor:#{factor}", "result:failed", "reason:not_supported"])
        if sms_2fa_not_enabled
          flash[:error] = "Two-factor SMS is not enabled."
        else
          flash[:error] = "Two-factor SMS is not allowed for one or more of your organizations. Please add an authenticator app and remove your SMS configuration."
        end
        return redirect_to settings_security_path
      end
    end

    TwoFactorSetup.start(current_user, skip_recovery_secret: true)
    current_user.two_factor_credential.instrument :configure_factor_start, factor: factor
    redirect_to settings_security_path(type: factor)
  end

  def two_factor_authentication_configure_factor_enable # rubocop:todo GitHub/UseRestfulActions
    two_factor_type = params[:type]

    unless current_user.two_factor_authentication_enabled?
      GitHub.dogstats.increment("two_factor.reconfigure_factor", tags: ["factor:#{two_factor_type}", "result:failed", "reason:two_factor_not_enabled"])
      flash[:error] = "Please enable two-factor authentication."
      return redirect_to settings_security_path
    end

    unless two_factor_type && RECONFIGURABLE_FACTORS.include?(two_factor_type)
      GitHub.dogstats.increment("two_factor.reconfigure_factor", tags: ["factor:#{two_factor_type}", "result:failed", "reason:invalid_type"])
      flash[:error] = "Cannot reconfigure '#{two_factor_type}' factor."
      return redirect_to settings_security_path
    end

    clear_two_factor_checkup_value
    reconfiguring = current_user.two_factor_configured_with?(two_factor_type.to_sym)
    reconfigured_text = reconfiguring ? "reconfigured" : "configured"
    if two_factor_type == "app" && TwoFactorSetup.configure_app(current_user)
      GitHub.dogstats.increment("two_factor.reconfigure_factor", tags: ["factor:#{two_factor_type}", "result:success"])
      flash[:notice] = "Authenticator app successfully #{reconfigured_text}."
    elsif two_factor_type == "sms" && TwoFactorSetup.configure_sms(current_user)
      GitHub.dogstats.increment("two_factor.reconfigure_factor", tags: ["factor:#{two_factor_type}", "result:success"])
      flash[:notice] = "SMS/Text message successfully #{reconfigured_text}."
    else
      error_type = two_factor_type == "app" ? "authenticator app" : "SMS/Text message"
      GitHub.dogstats.increment("two_factor.reconfigure_factor", tags: ["factor:#{two_factor_type}", "result:failed", "reason:error"])
      flash[:error] = "Reconfiguring #{error_type} failed."
    end
    redirect_to settings_security_path
  end

  def two_factor_authentication_disable_factor # rubocop:todo GitHub/UseRestfulActions
    factor = params[:type]
    return render_404 unless GitHub.two_factor_sms_enabled? # Enterprise does not support SMS

    unless factor && RECONFIGURABLE_FACTORS.include?(factor)
      GitHub.dogstats.increment("two_factor.disable_factor", tags: ["factor:#{factor}", "result:failed", "reason:invalid_type"])
      flash[:error] = "Cannot disable an invalid factor: '#{factor}'."
      return redirect_to settings_security_path
    end

    totp_app_registration = current_user.totp_app_registration
    sms_registration = current_user.two_factor_primary_sms_registration

    # if a user is trying to disable their last configured factor, we show and error and redirect them back to the settings security page
    unless totp_app_registration.present? && sms_registration.present?
      GitHub.dogstats.increment("two_factor.disable_factor", tags: ["factor:#{factor}", "result:failed", "reason:only_factor"])
      flash[:error] = "Cannot disable #{factor} currently, you need to have SMS and an Authenticator app enabled."
      return redirect_to settings_security_path
    end

    if factor == "app" && totp_app_registration.present?
      User.transaction do
        totp_app_registration.destroy!
        current_user.two_factor_credential.update!(login_preference: nil) if current_user.two_factor_credential&.app_preferred?
      end
      flash[:notice] = "Authenticator app successfully disabled."
      AccountMailer.two_factor_disable_factor(current_user, "authenticator app").deliver_later
    elsif factor == "sms" && sms_registration.present?
      # It was complaining about updating `updated_fallback`in the transaction block
      #   ie. hanging the type of a variable in a loop is not permitted
      # To get around this, we set it to `T.`untyped and then cast it to a boolean
      updated_fallback = T.let(false, T.untyped)

      User.transaction do
        if current_user.two_factor_backup_sms_registration?
          updated_fallback = current_user.promote_two_factor_sms_fallback_to_primary
        else
          sms_registration.destroy!
        end
        current_user.two_factor_credential.update!(login_preference: nil) if current_user.two_factor_credential&.sms_preferred? && !updated_fallback
      end

      if updated_fallback
        flash[:notice] = "Your fallback SMS number has been promoted to your primary SMS number."
      else
        flash[:notice] = "SMS/Text message successfully disabled."
      end
      AccountMailer.two_factor_disable_factor(current_user, "SMS", updated_fallback: updated_fallback).deliver_later
    else
      # users should not get into this state as we require both app and sms registrations to be present
      # this is in the unlikely scenario where factor is "app" but totp_app_registration does not exists and they have an sms_registration (and vice versa)
      GitHub.dogstats.increment("two_factor.disable_factor", tags: ["factor:#{factor}", "result:failed", "reason:error"])
      flash[:error] = "Disabling #{factor} failed. Please try again."
      return redirect_to settings_security_path
    end

    GitHub.dogstats.increment("two_factor.disable_factor", tags: ["factor:#{factor}", "result:success"])
    redirect_to settings_security_path
  end

  # Set a fallback sms number for two-factor authentication.
  #
  # Params:
  #  * countrycode - required
  #  * number      - required string fallback phone number
  #  * otp         - optional verification code sent to `number`
  #
  # Returns:
  #  * 201 - verified otp, set number as fallback
  #  * 202 - successfully sent otp to number, number not persisted
  #  * 422 - failed to send otp to number, or failed verification
  #
  def add_two_factor_sms_backup # rubocop:todo GitHub/UseRestfulActions
    # if we aren't _editing_ (e.g. they already have a backup sms registration) we 404 because we no
    # longer support _adding_ a backup sms number
    unless current_user.two_factor_backup_sms_registration?
      return render status: 404, json: { error: "We no longer support adding a fallback SMS number." }
    end

    raise GitHub::Messaging::NumberNotValidError unless GitHub::Messaging.valid_country_code?(params[:countrycode])

    number = "#{params[:countrycode]} #{params[:number]}"
    number = GitHub::Messaging.normalize_number(number)
    if params[:otp].present?
      valid, err = validate_two_factor_sms_backup_confirmation(
        number, params[:otp]
      )
      if valid
        provider = two_factor_sms_backup_confirmation_data[:provider]
        succeeded = current_user.edit_two_factor_sms_fallback(number, provider)
        if succeeded
          flash[:notice] = "Updated SMS fallback number."
          head 201
        else
          flash[:error] = "Failed to update SMS fallback number."
          head 500
        end
      else
        render status: 422, json: { error: err }
      end
    else
      if number == current_user.two_factor_sms_number
        render status: 422, json: { error: "Enter a number that is different from your primary SMS number." }
      else
        send_two_factor_sms_backup_setup_otp(number)
        head 202
      end
    end
  rescue GitHub::Messaging::Error => e
    render_sms_error 422, e.message
  end

  def validate_two_factor_sms_backup_confirmation(number, otp) # rubocop:todo GitHub/UseRestfulActions
    data = two_factor_sms_backup_confirmation_data
    valid_number = data[:number].present? && data[:number] == number
    valid_otp = data[:otp].present? &&
      SecurityUtils.secure_compare(data[:otp], otp)

    if valid_number && valid_otp
      [true, nil]
    elsif valid_number
      [false, "Verification failed. Please re-enter the OTP."]
    else
      [false, "Verification failed. Please add your number again."]
    end
  end

  def send_two_factor_sms_backup_setup_otp(number) # rubocop:todo GitHub/UseRestfulActions
    # Check to see if we have existing data from a recent prior attempt to setup
    # a backup SMS number.
    data = two_factor_sms_backup_confirmation_data

    last_used_provider = data[:provider]
    provider = GitHub::Messaging.provider_for(number, known_provider: current_user.two_factor_sms_provider(for_backup_number: false), last_used_provider: last_used_provider, attempt_alternate: !!last_used_provider)

    otp = 6.times.map { SecureRandom.random_number(10) }.join

    GitHub.dogstats.increment("authn_kv", tags: ["action:write", "callsite:two_factor_backup_number"])
    GitHub::Authentication::KV.store.set(
      add_two_factor_sms_backup_key,
      { number: number, otp: otp, provider: provider.provider_name }.to_json,
      expires: 10.minutes.from_now,
    )

    message = otp +
        " is your #{GitHub.flavor} SMS fallback setup code."

    message = add_origin_bound_sms_footer(message, otp)

    GitHub::Messaging.send_message(number, message, current_user, { provider: provider, reason: :two_factor_setup_fallback })
    GitHub.dogstats.increment("two_factor.setup_fallback_sms")
  end

  def two_factor_sms_backup_confirmation_data # rubocop:todo GitHub/UseRestfulActions
    GitHub.dogstats.increment("authn_kv", tags: ["action:read", "callsite:two_factor_backup_number"])
    data = GitHub::Authentication::KV.store.get(add_two_factor_sms_backup_key).value { "{}" }
    # The KV block value is only returned in case of an error. If the key is
    # simply expired that isn't considered an error and will return `nil`.
    data ||= "{}"
    data = JSON.parse(data).symbolize_keys
  end

  def add_two_factor_sms_backup_key # rubocop:todo GitHub/UseRestfulActions
    "AddTwoFactorSMSBackupOTP:#{current_user.two_factor_credential.id}"
  end

  def destroy_two_factor_sms_backup # rubocop:todo GitHub/UseRestfulActions
    succeeded = current_user.remove_two_factor_sms_fallback
    GitHub.dogstats.increment("two_factor.backup_number", tags: ["action:destroy", "result:#{succeeded ? 'success' : 'failure'}"])
    if succeeded
      flash[:notice] = "Removed SMS fallback number."
    else
      flash[:error] = "Failed to remove SMS fallback number."
    end
    redirect_to :back
  end

  def set_login_2fa_preference #rubocop:todo GitHub/UseRestfulActions
    error = "Unable to set your preferred login 2FA method, please make sure you have your chosen method configured."

    case params[:login_preference]
    when "sms_preferred"
      if current_user.two_factor_configured_with?(:sms)
        current_user.two_factor_credential.sms_preferred!
        GitHub.dogstats.increment("two_factor.preference", tags: ["factor:sms", "result:success"])
      else
        flash[:error] = error
        GitHub.dogstats.increment("two_factor.preference", tags: ["factor:sms", "result:failed"])
      end
    when "app_preferred"
      if current_user.two_factor_configured_with?(:app)
        current_user.two_factor_credential.app_preferred!
        GitHub.dogstats.increment("two_factor.preference", tags: ["factor:app", "result:success"])
      else
        flash[:error] = error
        GitHub.dogstats.increment("two_factor.preference", tags: ["factor:app", "result:failed"])
      end
    when "github_mobile_preferred"
      if current_user.gh_mobile_auth_available?
        current_user.two_factor_credential.github_mobile_preferred!
        GitHub.dogstats.increment("two_factor.preference", tags: ["factor:github_mobile", "result:success"])
      else
        flash[:error] = error
        GitHub.dogstats.increment("two_factor.preference", tags: ["factor:github_mobile", "result:failed"])
      end
    when "webauthn_preferred"
      if current_user.has_registered_security_key? || current_user.has_registered_passkey?
        current_user.two_factor_credential.webauthn_preferred!
        GitHub.dogstats.increment("two_factor.preference", tags: ["factor:webauthn", "result:success"])
      else
        flash[:error] = error
        GitHub.dogstats.increment("two_factor.preference", tags: ["factor:webauthn", "result:failed"])
      end
    end

    redirect_to :back
  end

  def ensure_two_factor_enabled # rubocop:todo GitHub/UseRestfulActions
    unless GitHub.auth.two_factor_authentication_enabled?
      render_404
    end
  end

  def ensure_user_has_two_factor_enabled # rubocop:todo GitHub/UseRestfulActions
    unless current_user.two_factor_authentication_enabled?
      if request.xhr?
        head 422
      else
        redirect_to settings_user_2fa_intro_path
      end
    end
  end

  def render_sms_error(status, text) # rubocop:todo GitHub/UseRestfulActions
    message = "We tried delivering an SMS to that number, but #{text}."
    render status: 422, json: { error: message }
  end

  private def two_factor_enforceable
    return :yes if TWO_FACTOR_ENABLED_ACTIONS.include?(action_name)
    :no
  end

  def sms_rate_limit_key # rubocop:todo GitHub/UseRestfulActions
    "2fa-sms:#{current_user.id}"
  end

  def render_sms_rate_limit # rubocop:todo GitHub/UseRestfulActions
    message = "You have exceeded our SMS rate limit. You will not be able to send another SMS for the next hour."
    GitHub.dogstats.increment("two_factor_setup.render_sms_rate_limit", tags: ["by:redis_rate_limitter"])
    render status: 422, json: { error: message }
  end

  def instrument_api_stats # rubocop:todo GitHub/UseRestfulActions
    tags = [
      "action:#{action_name}",
      "success:#{response.successful?}",
    ]
    tags.append("two_factor_type:#{params[:type]}") if params[:type]
    tags.append("inline_configure:#{!!params[:inline_configure]}")
    tags.append("two_factor_requirement_state:#{current_user.account_two_factor_requirement_state}") if current_user.account_two_factor_requirement_state
    tags.append("two_factor_requirement_state_requirement_reason:#{current_user.two_factor_requirement_metadata.requirement_reason}") if current_user.two_factor_requirement_metadata&.requirement_reason
    tags.append("two_factor_requirement_state_cohort:#{current_user.two_factor_requirement_metadata.cohort}") if current_user.two_factor_requirement_metadata&.cohort

    GitHub.dogstats.increment("two_factor.setup", tags: tags)
  end

  def holiday_warning_banner # rubocop:todo GitHub/UseRestfulActions
    unless session[:two_factor_holiday_warning_banner] == true
      return head :ok
    end

    render partial: "sessions/two_factor/holiday_warning_banner", locals: {
      passkeys_enabled: current_user.passkeys_enabled?,
    }
  end

  def dismiss_holiday_warning_banner # rubocop:todo GitHub/UseRestfulActions
    current_user.two_factor_holiday_warning_dismiss!
    session[:has_dismissed_two_factor_holiday_warning] = true
    GitHub.dogstats.increment("two_factor.holiday_warning_banner.dismissed")
    redirect_to :back
  end

  private

  def send_sms_verified_by_captcha?
    return true if !Octocaptcha.new(session, page: :two_factor_sms_setup, user: current_user).show_captcha?

    octocaptcha = Octocaptcha.new(session, params["octocaptcha-token"], page: :two_factor_sms_setup, user: current_user)
    octocaptcha.verify
    return true if octocaptcha.solved?

    # if there was an error loading captcha send a metric and report
    if params[:error_loading_captcha]
      GitHub.dogstats.increment("two_factor_sms_setup_captcha.error_loading_captcha")
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

  def instrument_sms_sent(sms_payload, number, callsite)
    GitHub.instrument("two_factor_authentication.send_primary_sms", sms_payload)
    current_user.sms_daily_rate_limit_increment(number)
    if current_user.feature_flag_enabled?(:publish_sms_sent_event, default: false)
      GlobalInstrumenter.instrument("two_factor.sms_message_sent", {
        actor: current_user,
        hashed_sms_number: Digest::SHA256.hexdigest(number),
      })
    end
  end
end
