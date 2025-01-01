# typed: strict
# frozen_string_literal: true

class OrgRoles::SettingsListComponent < ApplicationComponent
  extend T::Sig
  include GitHub::Memoizer

  sig { returns(Organization) }
  attr_reader :organization

  sig { returns(T::Hash[Symbol, T::Boolean]) }
  attr_reader :viewer_permissions

  sig { params(organization: Organization, viewer_permissions: T::Hash[Symbol, T::Boolean]).void }
  def initialize(organization:, viewer_permissions:)
    @organization = organization
    @viewer_permissions = viewer_permissions
  end

  sig { returns(String) }
  def custom_org_role_limit_message
    return "You have reached the limit (#{custom_org_role_limit}) of total allowed custom Organization roles." if is_org_role_limit_max?
    "Create a role and add permissions to it."
  end

  sig { returns(T::Boolean) }
  def is_org_role_limit_max?
    custom_org_roles.count >= custom_org_role_limit
  end

  sig { returns(T::Boolean) }
  def custom_org_roles_present?
    custom_org_roles.any?
  end

  private

  sig { returns(T::Array[OrganizationRole]) }
  memoize def custom_org_roles
    organization.custom_org_roles.includes(:permissions).to_a
  end

  sig { returns(T::Hash[[Integer, String], Integer]) }
  memoize def assignment_counts
    # Hash indexed by [role_id, actor_type] with values of the associated assignment count
    UserRole.where(target_type: "Organization", target_id: organization.id, role_id: custom_org_roles.map(&:id)).group(:role_id, :actor_type).count
  end

  sig { returns(Integer) }
  def custom_org_role_limit
    OrganizationRole.custom_role_limit_for_org(organization)
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
    role_assignment_count(role)["Team"] || 0
  end

  sig { params(role: OrganizationRole).returns(String) }
  def delete_path(role)
    delete_settings_org_roles_path(organization, role)
  end

  sig { params(role: OrganizationRole).returns(String) }
  def edit_path(role)
    edit_settings_org_roles_path(organization, role)
  end
end
