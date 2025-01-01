# typed: true
# frozen_string_literal: true

class Stafftools::Businesses::IpAllowlistEnabledController < Stafftools::Businesses::BusinessBaseController
  skip_before_action :dotcom_required

  def update
    if params[:reason].blank?
      flash[:error] = "You must provide a reason for updating the IP allow list enablement setting."
    else
      # Currently this only supports disabling the setting.
      if params[:enabled] == "false"
        this_business.disable_ip_allowlist actor: current_user, reason: params[:reason]
        flash[:notice] = "Disabled IP allow list."
      end
    end
    redirect_to stafftools_enterprise_security_path(this_business)
  end
end
