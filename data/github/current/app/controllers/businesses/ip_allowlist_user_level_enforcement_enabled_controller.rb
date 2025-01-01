# typed: true
# frozen_string_literal: true

class Businesses::IpAllowlistUserLevelEnforcementEnabledController < Businesses::BusinessController
  before_action :login_required
  before_action :business_owner_required
  before_action :eligible_business_required
  before_action :sudo_filter

  def update
    if params[:enable_ip_allowlist_user_level_enforcement] == "on"
      this_business.enable_ip_allowlist_user_level_enforcement(actor: current_user)
      flash[:notice] = "IP allow list user-level enforcement enabled."
    else
      this_business.disable_ip_allowlist_user_level_enforcement(actor: current_user)
      flash[:notice] = "IP allow list user-level enforcement disabled."
    end
    redirect_to settings_security_enterprise_path(this_business)
  end

  private

  def eligible_business_required
    render_404 unless this_business.eligible_for_ip_allowlist_user_level_enforcement?
  end
end
