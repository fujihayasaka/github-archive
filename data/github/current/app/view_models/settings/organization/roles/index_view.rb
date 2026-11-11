# typed: true
# frozen_string_literal: true

class Settings::Organization::Roles::IndexView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
  include Orgs::RolesHelper
  include EnterpriseManagedUsersHelper
  attr_reader :organization, :viewer_permissions

  def is_disabled?(role)
    return false if org_base_role.equal?(:none)
    role.action_rank < Ability::ACTION_RANKING[org_base_role]
  end

  def custom_role_message
    return "You have reached the limit (#{org_repo_role_limit}) of total allowed custom roles." if is_org_repo_role_limit_max?
    "Create a role by inheriting a pre-defined role and adding permissions to it."
  end

  def is_org_repo_role_limit_max?
    RepositoryRole.custom_roles_for_org(organization).count >= org_repo_role_limit
  end

  def org_repo_role_limit
    return @org_repo_role_limit if defined?(@org_repo_role_limit)
    @org_repo_role_limit = RepositoryRole.custom_role_limit_for_org(organization)
  end

  def delete_organisation_repository_role_path(role)
    urls.delete_settings_org_repository_roles_path(organization, role.id)
  end

  def role_invitation_count(role)
    RepositoryInvitation.where(role_id: role.id).count
  end

  def show_base_role_badge?(role_name)
    org_base_role?(role_name: role_name, organization: organization)
  end
end
