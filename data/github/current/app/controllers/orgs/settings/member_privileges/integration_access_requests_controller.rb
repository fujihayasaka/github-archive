# typed: true
# frozen_string_literal: true

class Orgs::Settings::MemberPrivileges::IntegrationAccessRequestsController < Orgs::Controller
  before_action :organization_admin_required

  ALLOW_OLD_ACCESS_REQUESTS_SETTINGS = {
    off: "0",
    on: "1",
  }.freeze

  ALLOW_APP_ACCESS_REQUESTS_SETTINGS = {
    allow_all: Configurable::OrgIntegrationRequestsConfiguration::ALLOW_ALL,
    allow_org_members_only: Configurable::OrgIntegrationRequestsConfiguration::ALLOW_ORG_MEMBERS_ONLY,
    disabled: Configurable::OrgIntegrationRequestsConfiguration::DISABLED,
  }.freeze

  def update
    # New setting
    if FeatureFlag.vexi.enabled?(:expanded_integration_requests_setting, current_organization, default: false)
      return render_error unless valid_parameter?
      notice = set_allow_access_requests!
    # Old setting flow - to be deprecated
    else
      return render_legacy_error unless valid_legacy_parameter?
      notice = set_legacy_allow_access_requests!
    end
    redirect_to :back, notice: notice
  end

  private

  # New flow
  def valid_parameter?
    ALLOW_APP_ACCESS_REQUESTS_SETTINGS.values.include?(params[:app_access_scope])
  end

  def render_error
    flash[:error] = "You specified an invalid value for the 'app access requests' setting."
    redirect_to :back
  end

  def set_allow_access_requests!
    if params[:app_access_scope] == ALLOW_APP_ACCESS_REQUESTS_SETTINGS[:allow_all]
      current_organization.allow_all_integration_requests(actor: current_user)
      current_organization.allow_third_party_access_requests_from_outside_collaborators(actor: current_user)
      "Members and outside collaborators are now allowed to make app access requests."
    elsif params[:app_access_scope] == ALLOW_APP_ACCESS_REQUESTS_SETTINGS[:allow_org_members_only]
      current_organization.allow_org_members_only_integration_requests(actor: current_user)
      current_organization.disallow_third_party_access_requests_from_outside_collaborators(actor: current_user)
      "App access requests are now restricted to members only. Outside collaborators can no longer make requests."
    else
      current_organization.disable_integration_requests(actor: current_user)
      current_organization.disallow_third_party_access_requests_from_outside_collaborators(actor: current_user) # Safest fallback since there is no equivalent mapping in the old config.
      "App access requests are now disabled for everyone."
    end
  end

  # Old flow - to be deprecated
  def valid_legacy_parameter?
    ALLOW_OLD_ACCESS_REQUESTS_SETTINGS.values.include?(params[:allow_access_requests])
  end

  def render_legacy_error
    flash[:error] = "You specified an invalid value for the 'outside collaborators can request app access' setting."
    redirect_to :back
  end

  def set_legacy_allow_access_requests!
    if params[:allow_access_requests] == ALLOW_OLD_ACCESS_REQUESTS_SETTINGS[:on]
      current_organization.allow_third_party_access_requests_from_outside_collaborators(actor: current_user)
      # Dual write as we transition to org_integration_request_configuration
      if FeatureFlag.vexi.enabled?(:write_to_org_integration_request_configuration_entries, current_organization, default: false)
        current_organization.allow_all_integration_requests(actor: current_user)
      end
      "Outside collaborators can now request app access."
    else
      current_organization.disallow_third_party_access_requests_from_outside_collaborators(actor: current_user)
      # Dual write as we transition to org_integration_request_configuration
      if FeatureFlag.vexi.enabled?(:write_to_org_integration_request_configuration_entries, current_organization, default: false)
        current_organization.allow_org_members_only_integration_requests(actor: current_user)
      end
      "Outside collaborators can no longer request app access."
    end
  end
end
