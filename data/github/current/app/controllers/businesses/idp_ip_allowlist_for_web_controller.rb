# typed: true
# frozen_string_literal: true

class Businesses::IdpIpAllowlistForWebController < Businesses::BusinessController
  include IdpIpAllowlistHelper

  before_action :login_required
  before_action :business_owner_required
  before_action :eligible_business_required
  before_action :sudo_filter

  def update
    idp_ip_allowlist_for_web = params[:idp_ip_allowlist_for_web]&.to_s

    if idp_ip_allowlist_for_web == "on"
      # check the IdP conditional access policy to ensure we won't lock out the current user
      enabling_will_lock_out_actor, error = enabling_idp_ip_allowlist_will_lock_out_actor?(business: this_business, actor: current_user, ip: remote_ip)

      if enabling_will_lock_out_actor
        flash[:error] = error if error
        return redirect_to settings_security_enterprise_path(this_business)
      end

      this_business.enable_idp_ip_allowlist_for_web(actor: current_user)
      flash[:notice] = "Identity Provider based IP allow list for web enabled."
    else
      this_business.disable_idp_ip_allowlist_for_web(actor: current_user)
      flash[:notice] = "Identity Provider based IP allow list for web disabled."
    end

    redirect_to settings_security_enterprise_path(this_business)
  end

  private

  def eligible_business_required
    unless this_business.eligible_for_idp_ip_allowlist_for_web_configurable?
      flash[:error] = Configurable::IdpIpAllowlistForWeb::UNSUPPORTED_ENTERPRISE_ERROR
      redirect_to settings_security_enterprise_path(this_business)
    end
  end

  def external_conditional_access_policy_enforceable
    if params[:idp_ip_allowlist_for_web]&.to_s == "on"
      # We manually check that IdP CAP is satisfied when enabling the setting and have special error handling, we don't need to do it twice
      :no
    else
      # If the setting is being disabled, it makes sense to check that IdP CAP is satisfied
      :yes
    end
  end
end
