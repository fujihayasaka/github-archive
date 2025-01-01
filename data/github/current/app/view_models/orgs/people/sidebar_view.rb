# typed: true
# frozen_string_literal: true

class Orgs::People::SidebarView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
  include BusinessesHelper
  include Orgs::People::RoleDescriptionMethods
  include Orgs::People::RoleNameMethods
  include UrlHelpers

  attr_reader :organization, :person, :repositories_count, :editable

  def role
    @role ||= Organization::Role.new(organization, person)
  end

  def repositories_count # rubocop:disable Lint/DuplicateMethods
    @repositories_count ||= organization.visible_repositories_for(person).size
  end

  def organization_roles_count
    team_ids = organization.teams_for(person, viewer: current_user).pluck(:id)
    business_team_ids = Orgs.domain.teams.business_team_ids_with_assigned_orgs_for(user_id: person.id, organization_id: organization.id) if organization.business&.erp_feature_enabled?(:enterprise_teams_org_roles)
    role_filter = OrganizationRole.visible_roles(organization)

    user_roles = UserRole.where(
      target_type: "Organization", target_id: organization.id,
      actor_type: "User", actor_id: person.id,
      role: role_filter
    ).count
    team_roles = UserRole.where(
      target_type: "Organization", target_id: organization.id,
      actor_type: "Team", actor_id: team_ids,
      role: role_filter
    ).count
    business_team_roles = if business_team_ids&.any?
      UserRole.where(
        target_type: "Organization", target_id: organization.id,
        actor_type: "BusinessTeam", actor_id: business_team_ids,
        role: role_filter
      ).count
    else
      0
    end

    user_roles + team_roles + business_team_roles
  end

  def organization_roles_assignment_path
    settings_org_role_assignments_path(organization, query: person.display_login)
  end

  def should_show_organization_roles_count?
    organization.adminable_by?(current_user)
  end

  def editable?
    !!editable
  end

  # Public: Is this member's org membership publicized?
  #
  # Returns a boolean.
  def public_member?
    organization.public_member?(person)
  end

  # Public: Can this user change this person's role?
  def can_change_role?
    return false unless editable?

    role.can_be_modified_by?(current_user) && !role.outside_collaborator?
  end

  # Public: Can this user publicize or conceal their membership in this org?
  def can_change_visibility?
    return false unless editable?

    if organization.public_member?(person)
      organization.can_conceal_memberships?(current_user, members: [person])
    else
      organization.can_publicize_memberships?(current_user, members: [person])
    end
  end

  def can_migrate_to_collaborator?
    repositories_count > 0
  end

  def hide_remove_from_org_button?
    if organization.business && EnterpriseTeam.enabled_for_organizations?(business: organization.business)
      return true if organization.prevent_removal_of_scim_managed_user?(user: person, reason: :enterprise_team)
    end

    scim_managed_enterprise?(organization.business) && organization.prevent_removal_of_scim_managed_user?(user: person, reason: :derived)
  end

  def show_billing_manager?
    GitHub.billing_enabled? && organization.billing_manager?(person)
  end

  # Public: Should the 2FA status for the person be shown? Only if 2FA is
  # enabled for the authentication system being used.
  #
  # Returns a Boolean
  def show_two_factor_status?
    return false if person.is_emu_and_not_first_owner?
    GitHub.auth.two_factor_authentication_enabled?
  end

  def show_sso_status?
    organization.saml_sso_present?
  end

  def sso_status
    return "" unless show_sso_status?

    sso_provider = if emu_oidc_target?(target: organization.external_identity_session_owner)
      organization.external_identity_session_owner.external_provider
    else
      organization.external_identity_session_owner.saml_provider
    end

    if sso_provider.external_identities.linked_to(person).exists?
      "SSO identity linked"
    else
      "No SSO identity linked"
    end
  end

  #  check feature flag state on a target
  def emu_oidc_target?(target:)
    target.present? && target.is_a?(Business) && target.oidc_enabled?
  end

  # Public: Do we show verified (and approved, if on GHES/AE) domain emails for this organization?
  # Checks if:
  #   - organization's plan supports showing verified domain emails
  #   - user is a member of this organization (don't want to ever show verified or approved domain
  #     emails for non-members)
  #   - the organization has any verified or approved domains (its own or via parent enterprise)
  #
  # Returns: Boolean
  def show_organization_domain_emails?
    return false unless organization.supports_showing_verified_domain_emails?
    return false unless person.organization_ids.include?(organization.id)

    organization_email_eligible_domains.any?
  end

  # Public: Returns an alphabetically sorted list of email addresses for this user coming from verified
  # and/or approved domains that the admin can see. Approved domain emails are only visible to admins on GHES/AE.
  #
  # Returns: Array[String] (array of email addresses)
  def admin_visible_domain_emails
    return [] unless organization.supports_showing_verified_domain_emails?

    user_emails = person.eligible_emails_for(organization)
    @user_has_approved_domain_email = !!user_emails.select! do |user_email|
      organization.show_user_email_address?(user_email)
    end

    user_emails.map(&:email).sort
  end

  def show_approved_domain_message?
    return false if VerifiableDomain.approved_domain_emails_visible_to_admins?

    @user_has_approved_domain_email
  end

  private

  def organization_email_eligible_domains
    @eligible_domains ||= VerifiableDomain.usable_for(organization).verified_or_approved
  end
end
