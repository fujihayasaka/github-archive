# typed: true
# frozen_string_literal: true

class Businesses::Organizations::SettingsMenuComponent < ApplicationComponent
  include HydroHelper

  GHAS_TEXT = "Advanced Security"

  def initialize(
    business:,
    organization:
  )
    @business = business
    @organization = organization
  end

  private

  def render?
    @business.present? && @organization.present? && logged_in?
  end

  def org_click_hydro_attributes
    hydro_click_tracking_attributes(
      "enterprise_account.profile_organization_click", {
        enterprise_id: @business.id,
        organization_id: @organization.id,
        actor_id: current_user.id
      }
    )
  end

  def option_available?(option)
    case option
    when :become_owner
      @business.owner?(current_user) && !current_user_owner_of_organization?
    when :become_member
      @business.owner?(current_user) && (!current_user_member_of_organization? || current_user_owner_of_organization?)
    when :leave_organization
      current_user_member_of_organization? && !current_user_has_business_team_membership_for_organization?
    when :organization_settings
      current_user_owner_of_organization? && !@business.downgraded_to_free_plan?
    when :transfer_organization
      @business.actor_can_transfer_organizations?(current_user)
    when :remove_organization
      !transfer_in_progress? &&
      !@business.enterprise_managed_user_enabled? &&
      @business.actor_can_remove_organizations?(current_user)
    when :organization_external_identity
      GitHub.flipper[:enterprise_idp_provisioning].enabled?(@business) &&
        !GitHub.single_business_environment? &&
        @business.owner?(current_user) && @business.saml_sso_enabled? && @organization.external_identity.present?
    else
      false
    end
  end

  memoize def current_user_owner_of_organization?
    @organization.adminable_by?(current_user)
  end

  memoize def current_user_member_of_organization?
    @organization.member?(current_user)
  end

  memoize def current_user_has_business_team_membership_for_organization?
    return false unless @business.erp_feature_enabled?(:enterprise_teams_org_assignment)
    Orgs.domain.teams.business_team_org_ids_for_user(user_id: current_user.id).any?
  end

  memoize def transfer_in_progress?
    BusinessOrganizationTransfer
      .where(from_business: @business, organization_id: @organization.id)
      .in_progress
      .any?
  end

  memoize def organization_saml_sso_enabled?
    @organization.saml_sso_enabled?
  end

  memoize def organization_saml_sso_enforced?
    @organization.saml_sso_enforced?
  end

  memoize def show_scim_warning?
    return false if current_user_member_of_organization? || @business.enterprise_managed_user_enabled? || @business.saml_sso_enabled?
    organization_saml_sso_enabled?
  end

  memoize def current_user_can_join_org?
    return false if organization_saml_sso_enforced? unless current_user_member_of_organization? || @business.saml_sso_enabled?
    true
  end

  memoize def org_cannot_be_transferred?
    BusinessOrganizationTransfer.new(
      from_business: @business,
      organization: @organization
    ).business_org_has_marketplace_subscriptions?
  end

  memoize def ghas_available?
    @business.advanced_security_purchased_for_entity?
  end

  memoize def copilot_available?
    @business.copilot_business.copilot_billable?
  end

  memoize def copilot_organization
    Copilot::Organization.new(@organization)
  end

  memoize def copilot_display_text
    "Copilot #{copilot_organization.copilot_plan.capitalize}"
  end

  def copilot_business_ghas_display_text
    if ghas_available? && copilot_available?
      "#{copilot_display_text} and #{GHAS_TEXT}"
    elsif ghas_available?
      GHAS_TEXT
    elsif copilot_available?
      copilot_display_text
    end
  end

  memoize def has_internal_repositories?
    @organization.internal_repositories.any?
  end
end
