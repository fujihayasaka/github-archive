# typed: true
# frozen_string_literal: true

class EditRepositories::Pages::MemberToolbarActionsView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
  attr_reader :repository, :selected_ids

  def selected_user_ids
    selected_ids[:user_ids] || []
  end

  def selected_invitation_ids
    selected_ids[:invitation_ids] || []
  end

  def selected_team_ids
    selected_ids[:team_ids] || []
  end

  def headcount
    selected_user_ids.count + selected_invitation_ids.count + selected_team_ids.count
  end

  def capitalized_base_role
    base_role.to_s.capitalize
  end

  def below_base_role?(role)
    return false if base_role == :none
    return false unless repository.organization&.member?(current_user)

    role_name = Role.valid_system_role?(role) ? role.to_sym : RepositoryRole.custom_role_by_name(role, owner: repository.organization).base_role.name.to_sym
    !RepositoryRole.target_greater_than_or_equal_to_other_role?(target: role_name, other_role: base_role)
  end

  def show_custom_roles?
    repository.owner.custom_roles_supported? && org_custom_roles.any?
  end

  def org_custom_roles
    return unless repository.owner.custom_roles_supported?
    repository.organization.custom_repo_roles
  end

  def role_applied_to_message
    "This role will only be applied to Outside Collaborators and Teams."
  end

  def plan_supports_fgp?
    return false unless repository.in_organization?
    repository.organization.plan_supports?(:fine_grained_permissions)
  end

  private

  def base_role
    repository.organization.default_repository_permission
  end
end
