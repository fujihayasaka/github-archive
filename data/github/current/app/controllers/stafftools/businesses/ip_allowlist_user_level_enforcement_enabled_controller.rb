# typed: true
# frozen_string_literal: true

class Stafftools::Businesses::IpAllowlistUserLevelEnforcementEnabledController < Stafftools::Businesses::BusinessBaseController
  skip_before_action :dotcom_required

  def update
    if params[:reason].blank?
      flash[:error] = "You must provide a reason for updating the IP allow list user-level enforcement setting."
    else
      # Currently this only supports disabling the setting.
      if params[:enabled] == "false"
        this_business.disable_ip_allowlist_user_level_enforcement actor: current_user, reason: params[:reason]
        flash[:notice] = "Disabled IP allow list user-level enforcement."
      end
    end
    redirect_to stafftools_enterprise_ip_allowlist_path(this_business)
  end
end
