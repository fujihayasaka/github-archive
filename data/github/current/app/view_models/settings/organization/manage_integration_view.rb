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
    actor_ids = Permissions::Enumerator.actor_ids_with_permission(
      action: :grantable_manage_app,
      subject_id: integration.id,
      context: { owner_id: organization.id },
    )

    organization.members(actor_ids: actor_ids)
      .includes(:profile)
      .where(["users.login LIKE :query OR profiles.name LIKE :query", { query: "%#{query}%" }])
      .references(:profile)
  end

  def beta_features?
    return true if launched_features?

    Integrations::ShowView::BETA_FEATURE_FLAGS.any? do |(global_flag, _opt_in)|
      GitHub.flipper[global_flag].enabled?(integration.owner)
    end
  end

  def launched_features?
    defined?(Integrations::ShowView::LAUNCHED_FEATURES) && Integrations::ShowView::LAUNCHED_FEATURES.any?
  end
end
