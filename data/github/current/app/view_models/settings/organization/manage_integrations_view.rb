# typed: true
# frozen_string_literal: true

class Settings::Organization::ManageIntegrationsView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
  attr_reader :organization, :integration, :query, :all_app_manager_ids, :owner_ids

  def this_app_managers
    @this_app_managers ||= all_users_with_app_management_permission.select do |user|
      this_app_manager_ids.include?(user.id)
    end
  end

  def all_app_managers
    @all_app_managers ||= all_users_with_app_management_permission.select do |user|
      all_app_manager_ids.include?(user.id)
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
    actor_ids = Permissions::Enumerator.actor_ids_with_permission(action: :grantable_manage_organization_apps, subject_id: organization.id)

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
        Permissions::Enumerator.actor_ids_with_permission(action: :manage_app, subject_id: integration.id)
      else
        []
      end
  end

  def all_users_with_app_management_permission
    @all_users ||=
      begin
        @all_app_manager_ids ||= Permissions::Enumerator.actor_ids_with_permission(action: :manage_all_apps, subject_id: organization.id)
        @owner_ids ||= Permissions::Enumerator.actor_ids_with_permission(action: :own_organization, subject_id: organization.id)
        User.where(id: owner_ids + all_app_manager_ids + this_app_manager_ids).includes(:profile)
      end
  end
end
