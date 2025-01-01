# typed: true
# frozen_string_literal: true

class Settings::Organization::ManageIntegrationsView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
  attr_reader :organization, :integration, :query, :autocomplete_query_suggestions, :all_app_manager_ids, :owner_ids, :all_user_app_manager_ids,
  :all_app_manager_team_ids, :all_app_manager_business_team_ids, :user_owner_ids

  def this_app_managers
    if Apps::ManagementHelper.teams_enabled_for_apps_management?(on: organization)
      teams = all_teams_with_app_management_permission.select do |team|
        this_app_team_manager_ids.include?(team.id)
      end

      business_teams = all_business_teams_with_app_management_permission.select do |team|
        this_app_business_team_manager_ids.include?(team.id)
      end

      users = all_users_with_app_management_permission_through_user.select do |user|
        this_app_user_manager_ids.include?(user.id)
      end

      @this_app_managers ||= teams + business_teams + users
    else
      @this_app_managers ||= all_users_with_app_management_permission.select do |user|
        this_app_manager_ids.include?(user.id)
      end
    end
  end

  def all_app_managers
    if Apps::ManagementHelper.teams_enabled_for_apps_management?(on: organization)
      teams = all_teams_with_app_management_permission.select do |team|
        all_app_manager_team_ids.include?(team.id)
      end

      business_teams = all_business_teams_with_app_management_permission.select do |team|
        all_app_manager_business_team_ids.include?(team.id)
      end

      users = all_users_with_app_management_permission_through_user.select do |user|
        all_user_app_manager_ids.include?(user.id)
      end

      @all_app_managers ||= teams + business_teams + users
    else
      @all_app_managers ||= all_users_with_app_management_permission.select do |user|
        all_app_manager_ids.include?(user.id)
      end
    end
  end

  # Public: Determine if "Install app" link should be shown. Full-trust GitHub
  # App installations should never be manually installed by end-users, so
  # "Install app" should never be visible for those apps. Otherwise, checks to
  # make sure the integration is installable anywhere by the current user.
  #
  # Returns a Boolean.
  def hide_install_app_section?
    return true unless Apps::Privileged.capable?(:user_installable, app: integration)
    return true unless integration.installable_by?(current_user)
    false
  end

  def organization_owners
    @organization_owners ||= all_users_with_app_management_permission.select do |user|
      owner_ids.include?(user.id)
    end
  end

  def suggestions
    actor_ids = Apps::ManagementHelper.user_ids_grantable_for_app_manager_role(on: organization)

    organization.members(actor_ids: actor_ids)
      .includes(:profile)
      .where(["users.login LIKE :query OR profiles.name LIKE :query", { query: "%#{query}%" }])
      .references(:profile)
  end

  def grant_path
    urls.settings_org_permissions_manage_integrations_grant_path(organization)
  end

  def suggestions_path
    urls.settings_org_permissions_manage_integrations_suggestions_path(organization)
  end

  def user_facing_app_url_text
    Integrations::ShowView.user_facing_app_url_text(integration)
  end

  private

  def this_app_manager_ids
    @this_app_manager_ids ||=
      if integration.present?
        Apps::ManagementHelper.user_ids_with_app_owner_role(on: integration)
      else
        []
      end
  end

  def this_app_user_manager_ids
    @this_app_user_manager_ids ||=
    if integration.present?
      Apps::ManagementHelper.user_ids_with_app_owner_role_directly_granted(on: integration)
    else
      []
    end
  end

  def this_app_team_manager_ids
    @this_app_team_manager_ids ||=
    if integration.present?
      Apps::ManagementHelper.team_ids_with_app_owner_role(on: integration)
    else
      []
    end
  end

  def this_app_business_team_manager_ids
    return [] unless Apps::ManagementHelper.business_teams_enabled_for_apps_management?(on: organization)

    @this_app_business_team_manager_ids ||= if integration.present?
      Apps::ManagementHelper.business_team_ids_with_app_owner_role(on: integration)
    else
      []
    end
  end

  def all_users_with_app_management_permission
    @all_users ||=
      begin
        @all_app_manager_ids ||= Apps::ManagementHelper.user_ids_with_app_manager_role(on: organization)
        @owner_ids ||= Permissions::Enumerator.actor_ids_with_permission(action: :own_organization, subject_id: organization.id)
        User.where(id: owner_ids + all_app_manager_ids + this_app_manager_ids).includes(:profile)
      end
  end

  def all_users_with_app_management_permission_through_user
    @all_user_managers ||=
      begin
        @all_user_app_manager_ids ||= Apps::ManagementHelper.user_ids_with_app_manager_role_directly_granted(on: organization)
        @user_owner_ids ||= Permissions::Enumerator.actor_ids_with_permission(action: :own_organization, subject_id: organization.id)
        User.where(id: user_owner_ids + all_user_app_manager_ids + this_app_user_manager_ids).includes(:profile)
      end
  end

  def all_teams_with_app_management_permission
    @all_teams ||=
      begin
        @all_app_manager_team_ids ||= Apps::ManagementHelper.team_ids_with_app_manager_role(on: organization)

        team_ids = all_app_manager_team_ids + this_app_team_manager_ids
        Team.where(id: team_ids)
      end
  end

  def all_business_teams_with_app_management_permission
    return [] unless Apps::ManagementHelper.business_teams_enabled_for_apps_management?(on: organization)

    @all_business_teams ||=
      begin
        @all_app_manager_business_team_ids ||= Apps::ManagementHelper.business_team_ids_with_app_manager_role(on: organization)

        business_team_ids = all_app_manager_business_team_ids + this_app_business_team_manager_ids
        BusinessTeam.where(id: business_team_ids)
      end
  end
end
