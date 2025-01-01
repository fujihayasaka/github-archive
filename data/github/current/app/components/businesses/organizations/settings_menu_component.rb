# typed: true
# frozen_string_literal: true

class Businesses::Organizations::SettingsMenuComponent < ApplicationComponent
  include HydroHelper

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
      !current_user_owner_of_organization?
    when :become_member
      !current_user_member_of_organization? || current_user_owner_of_organization?
    when :leave_organization
      current_user_member_of_organization?
    when :organization_settings
      current_user_owner_of_organization? && !@business.downgraded_to_free_plan?
    when :transfer_organization
      @business.actor_can_transfer_organizations?(actor: current_user)
    when :remove_organization
      !transfer_in_progress? &&
      !@business.enterprise_managed_user_enabled? &&
      @business.actor_can_remove_organizations?(actor: current_user)
    when :organization_external_identity
      GitHub.flipper[:enterprise_idp_provisioning].enabled?(@business) &&
        !GitHub.single_business_environment? &&
        @business.saml_sso_enabled? && @organization.external_identity.present?
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
end
