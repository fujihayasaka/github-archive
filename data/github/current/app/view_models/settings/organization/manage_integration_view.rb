# typed: true
# frozen_string_literal: true

class Settings::Organization::ManageIntegrationView < Settings::Organization::ManageIntegrationsView
  def grant_path
    urls.settings_org_permissions_integrations_managers_grant_path(organization, integration)
  end

  def suggestions_path
    urls.settings_org_permissions_integrations_managers_suggestions_path(organization, integration)
  end

  def suggestions
    if Apps::ManagementHelper.business_teams_enabled_for_apps_management?(on: organization)
      business_team_suggestions + team_suggestions + user_suggestions
    elsif Apps::ManagementHelper.teams_enabled_for_apps_management?(on: organization)
      team_suggestions + user_suggestions
    else
      actor_ids = Apps::ManagementHelper.user_ids_grantable_for_app_owner_role(on: integration)

      organization.members(actor_ids: actor_ids)
        .includes(:profile)
        .where(["users.login LIKE :query OR profiles.name LIKE :query", { query: "%#{query}%" }])
        .references(:profile)
    end
  end

  def user_suggestions
    actor_ids = Apps::ManagementHelper.user_ids_grantable_for_app_owner_role(on: integration)
    autocomplete_query_suggestions.select { |suggestion| suggestion.is_a?(User) && actor_ids.include?(suggestion.id) }
  end

  def team_suggestions
    team_ids = Apps::ManagementHelper.team_ids_grantable_for_app_owner_role(on: integration)
    autocomplete_query_suggestions.select { |suggestion| suggestion.is_a?(Team) && team_ids.include?(suggestion.id) }
  end

  def business_team_suggestions
    return [] unless Apps::ManagementHelper.business_teams_enabled_for_apps_management?(on: organization)
    team_ids = Apps::ManagementHelper.business_team_ids_grantable_for_app_owner_role(on: integration)
    BusinessTeam
      .where(id: team_ids)
      .where("name LIKE ?", "%#{query}%")
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
end
