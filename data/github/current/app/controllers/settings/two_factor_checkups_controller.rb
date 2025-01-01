# typed: true
# frozen_string_literal: true

class Settings::TwoFactorCheckupsController < ApplicationController
  include ApplicationHelper
  include Settings::ControllerMethods
  extend ActiveSupport::Concern

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Authnd,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show],
    optional: true

  before_action :login_required
  before_action :require_flagged_user
  skip_before_action :require_two_factor_checkup

  # This controller does not access protected organization resources
  private def resource_for_conditional_access
    :no_resource_for_conditional_access # rubocop:disable GitHub/SpecifyResourceForConditionalAccess
  end

  private def target_for_conditional_access
    :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end

  def show
    # if type is defined
    # try our best to show that type if possible
    # otherwise, show the first available type or a 404
    type = params[:type]
    return render_404 if !type.blank? && !%w[app sms].include?(type)

    if type.blank?
      # always use app if it's available as long as sms is not available _and_ preferred
      if current_user.two_factor_configured_with?(:app) && !current_user.two_factor_credential&.sms_preferred?
        type = "app"
      elsif current_user.two_factor_configured_with?(:sms)
        type = "sms"
      else
        # this is not an expected state, but we should handle it gracefully
        # take them to the "app" view since that's the safest default if this were to happen
        GitHub.dogstats.increment("two_factor_prompt_no_configured_methods", tags: ["action:checkup"])
        type = "app"
      end
    end

    return render_404 unless current_user.two_factor_configured_with?(type.to_sym)

    # send the user a text message if they're going to be prompted for an SMS OTP code
    begin
      current_user.send_two_factor_sms(callsite: :two_factor_checkup) if type == "sms"
    rescue GitHub::SMS::Error => e
      flash.now[:error] = sms_delivery_error_message(e.message)
    end

    render(
      "settings/two_factor_checkup/prompt",
      layout: "layouts/session_authentication",
      locals: { user: current_user, type: type.to_sym }
    )
  end

  def update
    otp, active_totp_type = GitHub::TwoFactorAuthentication.normalize_otp_from_params(params, action: "checkup")
    if active_totp_type.nil?
      GitHub.dogstats.increment("two_factor_checkups_update.no_specified_type")
      if current_user.two_factor_configured_with?(:app)
        active_totp_type = :app
      elsif current_user.two_factor_configured_with?(:sms)
        active_totp_type = :sms
      end
    end

    # if a user enters a recovery code instead of an authentication code, show the user an error
    # and have them try again with an authentication code
    if GitHub::TwoFactorAuthentication.recovery_code?(otp)
      flash[:error] = "It looks like you used a recovery code. Please try again with an authentication code."
      instrument_two_factor_checkup("failed", reason: "recovery_code")
      return safe_redirect_to session[:return_to]
    end

    # if a user enters a valid authentication code,
    # we want to clear the 2FA checkup date and redirect them to the success page
    if current_user.valid_otp?(otp, type: active_totp_type, callsite: "checkup")
      instrument_two_factor_checkup("success", type: active_totp_type)
      current_user.clear_two_factor_checkup_date(force_hit_kv = true)
      enable_sudo(active_totp_type) # enable sudo mode for the user, avoids additional hassle for recovery code download

      render(
        "settings/two_factor_checkup/success",
        layout: "layouts/session_authentication",
        locals: { user: current_user, return_to: session[:return_to] }
      )
    else
      if current_user.reused_valid_totp?(otp, type: active_totp_type)
        message = ["The authentication code you entered has already been used or is too old to be used."]
        if current_user.two_factor_sms_enabled? && active_totp_type == :sms && otp != current_user.two_factor_sms_totp.now
          begin
            current_user.send_two_factor_sms(callsite: :two_factor_checkup_authenticate_resend)
            message << "A new code has been sent to your phone."
          rescue GitHub::SMS::Error => e
            message << sms_delivery_error_message(e.message)
          end
        end
        flash.now[:error] = message.join(" ")
        instrument_two_factor_checkup("failed", reason: "reused_code", type: active_totp_type)
      else
        instrument_two_factor_checkup("failed", reason: "invalid_code", type: active_totp_type)
        flash.now[:error] = "Two factor authentication failed."
      end

      render(
        "settings/two_factor_checkup/prompt",
        layout: "layouts/session_authentication",
        locals: { user: current_user, type: active_totp_type || :app }
      )
    end
  end

  def edit
    delay_success = current_user.increment_two_factor_checkup_delay_count

    if !delay_success
      flash[:error] = "2FA verification can no longer be delayed. Please complete the 2FA checkup to continue."
    end

    safe_redirect_to session[:return_to]
  end

  private

  def require_flagged_user
    return if current_user.is_due_for_two_factor_checkup?

    return safe_redirect_to session[:return_to] if !!session[:return_to]
    render_404
  end

  def instrument_two_factor_checkup(result, reason: nil, type: nil)
    GitHub.dogstats.increment("two_factor_checkup", tags: ["result:#{result}", "two_factor_type:#{type || "unknown"}", "reason:#{reason}"])
  end

  def sms_delivery_error_message(message)
    "We tried sending an SMS to your configured number, but #{message}." +
    " Please contact support if you continue to have problems."
  end
end
