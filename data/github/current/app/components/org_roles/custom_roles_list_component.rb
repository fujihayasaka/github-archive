# typed: strict
# frozen_string_literal: true

class OrgRoles::CustomRolesListComponent < ApplicationComponent
  include GitHub::Memoizer

  sig { returns(Organization) }
  attr_reader :organization

  sig { returns(T::Hash[Symbol, T::Boolean]) }
  attr_reader :viewer_permissions

  sig { returns(T.untyped) }
  attr_reader :system_arguments

  sig do
    params(
      organization: Organization,
      viewer_permissions: T::Hash[Symbol, T::Boolean],
      system_arguments: Primer::SystemArgumentsValue,
    ).void
  end
  def initialize(organization:, viewer_permissions:, **system_arguments)
    @organization = organization
    @viewer_permissions = viewer_permissions
    @system_arguments = system_arguments
  end

  sig { returns(String) }
  def subheading_text
    return "These roles are created and managed by organization administrators or by the owning enterprise (if indicated)." if viewer_permissions[:stafftools]

    if custom_role_limit_reached?
      "You have reached the limit (#{custom_role_limit}) of total allowed custom organization roles."
    else
      "Create a role and add permissions to it."
    end
  end

  private

  sig { returns(T::Array[OrganizationRole]) }
  memoize def custom_roles
    organization.custom_org_roles.includes(:permissions).to_a
  end

  sig { returns(Integer) }
  def custom_role_count
    custom_roles.size
  end

  sig { returns(Integer) }
  def custom_role_limit
    OrganizationRole.custom_role_limit_for_org(organization)
  end

  sig { returns(T::Boolean) }
  def custom_role_limit_reached?
    custom_role_count >= custom_role_limit
  end

  sig { returns(T::Hash[[Integer, String], Integer]) }
  memoize def assignment_counts
    # Hash indexed by [role_id, actor_type] with values of the associated assignment count
    UserRole.where(target_type: "Organization", target_id: organization.id, role_id: custom_roles.map(&:id)).group(:role_id, :actor_type).count
  end

  # returns Hash indexed by actor_type (i.e. "User", or "Team")
  sig { params(role: OrganizationRole).returns(T::Hash[String, Integer]) }
  def role_assignment_count(role)
    assignment_counts.select { |k, _| k[0] == role.id }.transform_keys { |k| k[1] }
  end

  sig { params(role: OrganizationRole).returns(Integer) }
  def role_user_count(role)
    role_assignment_count(role)["User"] || 0
  end

  sig { params(role: OrganizationRole).returns(Integer) }
  def role_team_count(role)
    team_count = role_assignment_count(role)["Team"] || 0
    team_count += role_business_team_count(role) if supports_business_teams?
    team_count
  end

  sig { params(role: OrganizationRole).returns(Integer) }
  def role_business_team_count(role)
    role_assignment_count(role)["BusinessTeam"] || 0
  end

  # returns false if viewer does not have write permissions
  # returns false for enterprise-owned roles
  sig { params(role: OrganizationRole).returns(T::Boolean) }
  def editable_role?(role)
    return false unless viewer_permissions[:write]

    role.owner_type == "Organization"
  end

  sig { params(role: OrganizationRole).returns(T::Boolean) }
  def enterprise_owned_org_role?(role)
    role.owner_type == "Business" && role.owner.present?
  end

  sig { returns(T::Boolean) }
  memoize def supports_business_teams?
    !!@organization.business&.enterprise_teams_org_roles_supported?
  end
end
