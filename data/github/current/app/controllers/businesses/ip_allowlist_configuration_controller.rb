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
end
