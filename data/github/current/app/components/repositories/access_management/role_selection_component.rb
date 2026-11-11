# typed: true
# frozen_string_literal: true

class Repositories::AccessManagement::RoleSelectionComponent < ApplicationComponent
  include Orgs::RolesHelper
  include Repos::AccessManagementDependency
  attr_reader :repository, :new_style

  def initialize(repository:, new_style: false)
    @repository = repository
    @new_style = new_style
  end

  def show_role_details?
    repository.owner.custom_roles_supported? && repository.adminable_by?(current_user)
  end

  def disabled_role?(role)
    return false unless repository.in_organization?

    role_name = if Role.valid_system_role?(role)
      role.to_sym
    else
      Role.base_role_name_or_self(role, owner: repository.organization).to_sym
    end

    default_perm = organization_base_role(organization: repository.organization)
    !RepositoryRole.target_greater_than_or_equal_to_other_role?(target: role_name, other_role: default_perm)
  end

  def show_base_role_badge?(role_name)
    return false if is_user_fork_of_private_org_repo?
    org_base_role?(role_name: role_name, organization: repository.organization)
  end

  def plan_supports_fgp?
    return false if is_user_fork_of_private_org_repo?
    return false unless repository.in_organization?
    repository.organization.plan_supports?(:fine_grained_permissions)
  end

  def show_custom_roles?
    repository.owner.custom_roles_supported? && org_custom_repo_roles.any?
  end

  def org_custom_repo_roles
    return unless repository.owner.custom_roles_supported?
    repository.organization.custom_repo_roles
  end

  private

  memoize def custom_roles_supported?
    repository.owner.custom_roles_supported?
  end
end
