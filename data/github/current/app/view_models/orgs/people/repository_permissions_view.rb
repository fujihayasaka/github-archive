# typed: true
# frozen_string_literal: true

class Orgs::People::RepositoryPermissionsView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
  attr_reader :organization
  attr_reader :person
  attr_reader :repository

  def repository_permissions
    @repository_permissions ||= Organization::RepositoryPermissions.new(repository, person)
  end

  # repo_permission returns the name of the highest permission/role as a string
  def repository_permission
    return @repository_permission if defined?(@repository_permission)
    @repository_permission = repository.async_action_or_role_level_for(person).sync
  end

  def show_revoke_all_repo_access_button?
    return if repository_permissions.active_abilities.empty?
    return if repository.owner == person

    !organization.adminable_by?(person)
  end

  def revoke_all_repo_access_button_enabled?
    repository_permissions.organization_ability.blank? ||
      role.outside_collaborator?
  end

  def show_revoke_active_repo_access_button?
    show_revoke_all_repo_access_button? &&
      repository_permissions.inactive_abilities.any?
  end

  def revoke_active_repo_access_button_enabled?
    repository_permissions.active_abilities.exclude?(repository_permissions.organization_ability) ||
      role.outside_collaborator?
  end

  def will_retain_access?
    repository_permissions.permission_after_revoking_active.present?
  end

  private

  def role
    @role ||= organization.role_of(person)
  end
end
