# typed: strict
# frozen_string_literal: true

class Businesses::CustomRoles::OrgRolesListComponent < ApplicationComponent
  include GitHub::Memoizer

  sig { returns(Business) }
  attr_reader :business

  sig { returns(T::Hash[Symbol, T::Boolean]) }
  attr_reader :viewer_permissions

  sig { returns(T.untyped) }
  attr_reader :system_arguments

  sig do
    params(
      business: Business,
      viewer_permissions: T::Hash[Symbol, T::Boolean],
      system_arguments: Primer::SystemArgumentsValue,
    ).void
  end
  def initialize(business:, viewer_permissions:, **system_arguments)
    @business = business
    @viewer_permissions = viewer_permissions
    @system_arguments = system_arguments
  end

  sig { returns(String) }
  def subheading_text
    if custom_role_limit_reached?
      "You have reached the limit (#{custom_role_limit}) of total allowed custom business roles."
    else
      "Create a role and add permissions to it. You can create up to #{custom_role_limit} custom roles to fit your needs."
    end
  end

  private

  sig { returns(T::Array[OrganizationRole]) }
  memoize def custom_roles
    OrganizationRole.includes(:permissions).custom_roles_for_enterprise(business).to_a
  end

  sig { returns(Integer) }
  def custom_role_count
    custom_roles.size
  end

  sig { returns(Integer) }
  def custom_role_limit
    OrganizationRole.custom_role_limit_for_owner(business)
  end

  sig { returns(T::Boolean) }
  def custom_role_limit_reached?
    custom_role_count >= custom_role_limit
  end

  sig { returns(T::Hash[[Integer, String], Integer]) }
  memoize def assignment_counts
    # Hash indexed by [role_id, actor_type] with values of the associated assignment count
    UserRole.where(target_type: "Organization", role_id: custom_roles.map(&:id)).group(:role_id, :actor_type).count
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
end
