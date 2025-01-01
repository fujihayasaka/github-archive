# typed: true
# frozen_string_literal: true

class Businesses::SkipIdpIpAllowlistAppAccessEnabledController < Businesses::BusinessController
  before_action :login_required
  before_action :business_owner_required
  before_action :eligible_business_required
  before_action :sudo_filter

  def update
    if params[:enable_skip_idp_ip_allowlist_app_access] == "on"
      this_business.enable_skip_idp_ip_allowlist_app_access(actor: current_user)
      flash[:notice] = "Skip IdP IP allow list configuration for applications enabled."
    else
      this_business.disable_skip_idp_ip_allowlist_app_access(actor: current_user)
      flash[:notice] = "Skip IdP IP allow list configuration for applications disabled."
    end
    redirect_to settings_security_enterprise_path(this_business)
  end

  private

  def eligible_business_required
    render_404 unless this_business.eligible_for_skip_idp_ip_allowlist_app_access?
  end
end
