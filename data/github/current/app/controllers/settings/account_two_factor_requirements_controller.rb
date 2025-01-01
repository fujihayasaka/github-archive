# typed: true
# frozen_string_literal: true

class Settings::AccountTwoFactorRequirementsController < ApplicationController
  include Settings::ControllerMethods

  before_action :login_required

  def dismiss_banner # rubocop:todo GitHub/UseRestfulActions
    if current_user.two_factor_requirement_metadata.nil?
      GitHub.dogstats.increment("account_2fa_requirement_interrupt.missing_metadata", tags: ["from:dismiss_banner"])
      clear_account_2fa_requirement_banner_values
      return redirect_to :back
    end

    current_user.update_2fa_requirement_banner_metadata
    # clear banner values to reevaluate if the user should see the banner
    clear_account_2fa_requirement_banner_values

    GitHub.dogstats.increment("account_2fa_requirement_interrupt.dismiss_enrollment_banner", tags: ["cohort:#{current_user.two_factor_requirement_metadata&.cohort}", "requirement_reason:#{current_user.two_factor_requirement_metadata&.requirement_reason}", "action:#{params[:banner_action]}"])

    case params[:banner_action]
    when "manage"
      redirect_to settings_security_path
    when "enable"
      redirect_to settings_user_2fa_intro_path
    else
      redirect_to :back
    end
  end

  def interrupt # rubocop:todo GitHub/UseRestfulActions
    GitHub.dogstats.increment("account_2fa_requirement_interrupt", tags: ["action:#{params[:type] || "unknown"}"])
    case params[:type]
    when "setup"
      return redirect_to settings_user_2fa_intro_path(return_to: params[:return_to])
    when "bypass"
      if current_user.can_bypass_account_2fa_requirement_interrupt?
        current_user.set_bypass_account_2fa_requirement_interrupt!
      else
        flash[:error] = "You must configure two-factor authentication before you can continue."
        return redirect_to settings_user_2fa_intro_path(return_to: params[:return_to])
      end
    end
    safe_redirect_to params[:return_to]
  end
end
