# typed: true
# frozen_string_literal: true

require "oidc/cap_validator"

class Businesses::IpAllowlistConfigurationController < Businesses::BusinessController
  include IdpIpAllowlistHelper

  before_action :login_required
  before_action :business_owner_required
  before_action :eligible_business_required
  before_action :sudo_filter

  DISABLED_VALUE = "disabled"
  IDP_VALUE = "idp"
  GITHUB_VALUE = "github"
  ALL_VALUES = [DISABLED_VALUE, IDP_VALUE, GITHUB_VALUE].freeze

  def update
    ip_allowlist_configuration = params[:ip_allowlist_configuration]&.to_s
    validate_setting value: ip_allowlist_configuration, valid_values: ALL_VALUES

    if enabling_idp_will_lock_out_actor?(ip_allowlist_configuration)
      return redirect_to settings_security_enterprise_path(this_business)
    end

    case ip_allowlist_configuration
    when IDP_VALUE
      this_business.disable_ip_allowlist_for_business_and_orgs(actor: current_user, reason: "IP configuration changed to IdP managed")
    when DISABLED_VALUE
      this_business.disable_ip_allowlist(actor: current_user, reason: "IP configuration changed to disabled")
    end

    this_business.update_ip_allowlist_configuration(actor: current_user, config_value: ip_allowlist_configuration)

    case ip_allowlist_configuration
    when IDP_VALUE
      flash[:notice] = "IdP based IP allow list enabled"
    when GITHUB_VALUE
      flash[:notice] = "GitHub based IP allow list enabled"
    else
      flash[:notice] = "IP allow list disabled"
    end

    redirect_to settings_security_enterprise_path(this_business)
  end

  private

  def eligible_business_required
    render_404 unless this_business.eligible_for_ip_allowlist_configuration?
  end

  # Will enabling the IdP IP allowlist cause a web lockout for the current user?
  # Checks that the IP is allowed by the IdP CAP.
  def enabling_idp_will_lock_out_actor?(ip_allowlist_configuration)
    # Only applicable if the configuration is being set to IDP
    return false unless ip_allowlist_configuration == IDP_VALUE

    # Only check for lockouts when web is included as part of IdP CAP
    return false unless this_business.feature_enabled?(:idp_cap_for_web)

    # Businesses with `idp_cap_web_configurable_allowed` enabled are existing customers
    # already using IdP CAP for API and gitauth. Don't check IP on enablement for these businesses,
    # check instead when configurable is enabled for web.
    return false if this_business.feature_enabled?(:idp_cap_web_configurable_allowed)

    enabling_will_lock_out_actor, error = enabling_idp_ip_allowlist_will_lock_out_actor?(business: this_business, actor: current_user, ip: remote_ip)

    if enabling_will_lock_out_actor
      flash[:error] = error if error
    end

    enabling_will_lock_out_actor
  end
end
