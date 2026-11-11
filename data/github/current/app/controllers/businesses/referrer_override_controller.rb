# typed: true
# frozen_string_literal: true

class Businesses::ReferrerOverrideController < Businesses::BusinessController
  before_action :enterprise_required
  before_action :login_required
  before_action :business_owner_required
  before_action :sudo_filter

  def update
    referrer_override_enabled = params[:referrer_override]&.to_s
    message = if referrer_override_enabled == "enabled"
      this_business.enable_referrer_override(actor: current_user)
      "Enabled referrer policy override."
    elsif referrer_override_enabled == "disabled"
      this_business.disable_referrer_override(actor: current_user)
      "Disabled referrer policy override."
    else
      flash[:error] = "Invalid value for referrer override selection. Please specify whether to enable or disable the setting."
      return redirect_to settings_security_enterprise_path(this_business)
    end
    redirect_to settings_security_enterprise_path(this_business), notice: message
  end
end
