# typed: true
# frozen_string_literal: true

class Businesses::ManageIntegrationRolesView < ViewModel  # rubocop:todo ViewComponent/NoMoreViewModels
  attr_reader :business, :integration, :query, :all_user_app_manager_ids,
   :all_app_manager_business_team_ids, :user_owner_ids, :autocomplete_query_suggestions

  def grant_path
    urls.settings_permissions_apps_create_enterprise_path(business, integration)
  end

  def suggestions_path
    urls.settings_permissions_apps_suggestions_enterprise_path(business, integration)
  end

  def beta_features?
    return true if launched_features?

    Integrations::ShowView::BETA_FEATURE_FLAGS.any? do |(global_flag, _opt_in)|
      FeatureFlag.vexi.enabled_or_raise?(global_flag, integration.owner) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
    end
  end

  def launched_features?
    defined?(Integrations::ShowView::LAUNCHED_FEATURES) && Integrations::ShowView::LAUNCHED_FEATURES.any?
  end

  def suggestions
    if business.erp_feature_enabled?(:enterprise_teams_crud)
      business_team_suggestions + user_suggestions
    else
      user_suggestions
    end
  end

  def user_suggestions
    actor_ids = Apps::ManagementHelper.user_ids_grantable_for_app_owner_role(on: integration)

    User.where(id: actor_ids)
      .includes(:profile)
      .where(["users.login LIKE :query OR profiles.name LIKE :query", { query: "%#{query}%" }])
      .references(:profile)
  end

  def business_team_suggestions
    team_ids = Apps::ManagementHelper.business_team_ids_grantable_for_app_owner_role(on: integration)
    BusinessTeam
      .where(id: team_ids)
      .where("name LIKE ?", "%#{query}%")
  end

  def this_app_managers
    business_teams = all_business_teams_with_app_management_permission.select do |team|
      this_app_business_team_manager_ids.include?(team.id)
    end

    users = all_users_with_app_management_permission_through_user.select do |user|
      this_app_user_manager_ids.include?(user.id)
    end

    @this_app_managers ||= business_teams + users
  end

  def all_app_managers
    business_teams = all_business_teams_with_app_management_permission.select do |team|
      all_app_manager_business_team_ids.include?(team.id)
    end

    users = all_users_with_app_management_permission_through_user.select do |user|
      all_user_app_manager_ids.include?(user.id)
    end

    @all_app_managers ||= business_teams + users
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

  def business_owners
    business.owners.pluck(:id)
  end

  def user_facing_app_url_text
    Integrations::ShowView.user_facing_app_url_text(integration)
  end

  def show_app_managers?
    integration.owner.owners.include?(current_user)
  end

  def app_managers_path
    Rails.application.routes.url_helpers.settings_permissions_apps_managers_enterprise_path(integration.owner, integration)
  end

  private

  def this_app_user_manager_ids
    @this_app_user_manager_ids ||=
    if integration.present?
      Apps::ManagementHelper.user_ids_with_app_owner_role_directly_granted(on: integration)
    else
      []
    end
  end

  def this_app_business_team_manager_ids
    @this_app_business_team_manager_ids ||= if integration.present?
      Apps::ManagementHelper.business_team_ids_with_app_owner_role(on: integration)
    else
      []
    end
  end

  def all_users_with_app_management_permission_through_user
    @all_user_managers ||=
      begin
        @all_user_app_manager_ids ||= Apps::ManagementHelper.user_ids_with_app_manager_role_directly_granted(on: business)
        @user_owner_ids ||= Permissions::Enumerator.actor_ids_with_permission(action: :own_organization, subject_id: business.id)
        User.where(id: user_owner_ids + all_user_app_manager_ids + this_app_user_manager_ids).includes(:profile)
      end
  end

  def all_business_teams_with_app_management_permission
    @all_business_teams ||=
      begin
        @all_app_manager_business_team_ids ||= Apps::ManagementHelper.business_team_ids_with_app_manager_role(on: business)

        business_team_ids = all_app_manager_business_team_ids + this_app_business_team_manager_ids
        BusinessTeam.where(id: business_team_ids)
      end
  end
end
