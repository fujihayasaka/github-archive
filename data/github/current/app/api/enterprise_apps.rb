# typed: true
# frozen_string_literal: true

class Api::EnterpriseApps < Api::Enterprise::App
  get "/enterprises/:enterprise_id/apps/installable_organizations", operation_id: "enterprise-apps/installable-organizations" do
    current_enterprise = find_enterprise!

    deliver_error!(404) unless GitHub.flipper[:enterprise_app_installation_management].enabled?(current_enterprise)

    control_access :list_installable_enterprise_organizations,
      resource: current_enterprise,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    orgs = paginate_rel(current_enterprise.organizations.includes(:business))

    deliver :enterprise_installable_organizations_hash, orgs
  end

  get "/enterprises/:enterprise_id/apps/organizations/:org/installations", operation_id: "enterprise-apps/organization-installations" do
    current_enterprise = find_enterprise!
    deliver_error!(404) unless current_enterprise.feature_enabled?(:enterprise_app_installation_management)

    control_access :list_enterprise_organization_installations,
      resource: current_enterprise,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    current_organization = find_org!
    deliver_error!(404) unless current_organization.business == current_enterprise

    scope = IntegrationInstallation.user_installable.with_target(current_organization)
    paginated_installations = paginate_rel(scope).load

    GitHub::PrefillAssociations.prefill_associations(
      paginated_installations,
      [:event_records, :integration, :target, :version],
      available_records: [current_enterprise]
    )

    deliver :enterprise_organization_installation_hash, paginated_installations
  end

  get "/enterprises/:enterprise_id/apps/organizations/:org/installations/:installation_id/repositories", operation_id: "enterprise-apps/organization-installation-repositories" do
    current_enterprise = find_enterprise!
    deliver_error!(404) unless current_enterprise.feature_enabled?(:enterprise_app_installation_management)

    control_access :list_enterprise_organization_installation_repositories,
      resource: current_enterprise,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    current_organization = find_org!
    deliver_error!(404) unless current_organization.business == current_enterprise

    current_installation = IntegrationInstallation.user_installable.with_target(current_organization).find_by(id: params[:installation_id])
    deliver_error!(404) unless current_installation

    paginated_repositories = paginate_rel(current_installation.repositories)

    deliver :enterprise_organization_installation_repositories_hash, paginated_repositories
  end

  post "/enterprises/:enterprise_id/apps/organizations/:org/installations", operation_id: "enterprise-apps/create-installation" do
    current_enterprise = find_enterprise!

    deliver_error!(404) unless current_enterprise.feature_enabled?(:enterprise_app_installation_management)

    control_access :install_for_enterprise_organizations,
      resource: current_enterprise,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    org = find_org!

    deliver_error!(403) unless org.business == current_enterprise

    data = receive_with_openapi

    integration = Integration.find_by(key: data["client_id"])
    deliver_error!(404) unless integration

    if current_installation = integration.installations.find_by(target: org)
      unless current_installation.outdated?
        return deliver :installation_hash, current_installation, status: 200
      end

      result = current_installation.update_version(
        editor: current_user,
        version: integration.latest_version,
        entry_point: :rest_api_enterprise_apps_create_installation
      )

      if result.success?
        return deliver :installation_hash, current_installation, status: 200
      else
        deliver_error!(400, message: result.error)
      end
    end

    if integration.pending_installation_requests.where(target: org).exists?
      integration.pending_installation_requests.where(target: org).each do |request|
        request.close(reason: "approved", actor: current_user)
      end
    end

    repositories = if data["repository_selection"] == "all"
      nil
    else
      if data.fetch("repositories", []).any?
        org.repositories.where(name: data["repositories"])
      else
        :none
      end
    end

    result = integration.install_on(
      org,
      repositories: repositories,
      installer: current_user,
      entry_point: :rest_api_enterprise_apps_create_installation
    )

    if result.success?
      deliver :installation_hash, result.installation, status: 201
    else
      deliver_error!(400, message: result.error)
    end
  end

  get "/enterprises/:enterprise_id/apps/installable_organizations/:org/accessible_repositories", operation_id: "enterprise-apps/installable-organization-accessible-repositories" do
    current_enterprise = find_enterprise!
    deliver_error!(404) unless GitHub.flipper[:enterprise_app_installation_management].enabled?(current_enterprise)

    control_access :list_installable_enterprise_organization_accessible_repositories,
      resource: current_enterprise,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    current_organization = find_org!
    deliver_error!(404) unless current_organization.business == current_enterprise

    repos = paginate_rel(current_organization.repositories)

    deliver :enterprise_installable_organization_accessible_repositories_hash, repos
  end

  patch "/enterprises/:enterprise_id/apps/organizations/:org/installations/:installation_id/repositories/add", operation_id: "enterprise-apps/grant-repository-access-to-installation" do
    current_enterprise = find_enterprise!
    deliver_error!(404) unless current_enterprise&.feature_enabled?(:enterprise_app_installation_management)

    control_access :update_enterprise_organization_installation_repositories,
      resource: current_enterprise,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    current_organization = find_org!
    deliver_error!(404) unless current_organization.business == current_enterprise

    installation = IntegrationInstallation.user_installable.with_target(current_organization).find_by(id: params[:installation_id])
    deliver_error!(404) unless installation

    data = receive_with_openapi
    repositories = current_organization.repositories.where(name: data["repositories"])

    result = IntegrationInstallation::RepositoryEditor.perform(
      installation,
      action: :add_from_api,
      repositories: repositories,
      editor: current_user,
      entry_point: :rest_api_enterprise_apps_grant_repository_access_to_installation
    )

    if result.success?
      deliver :enterprise_installable_organization_accessible_repositories_hash, repositories
    else
      deliver_error!(400, message: result.error)
    end
  end

  patch "/enterprises/:enterprise_id/apps/organizations/:org/installations/:installation_id/repositories/remove", operation_id: "enterprise-apps/remove-repository-access-to-installation" do
    current_enterprise = find_enterprise!
    deliver_error!(404) unless current_enterprise&.feature_enabled?(:enterprise_app_installation_management)

    control_access :update_enterprise_organization_installation_repositories,
      resource: current_enterprise,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    current_organization = find_org!
    deliver_error!(404) unless current_organization.business == current_enterprise

    installation = IntegrationInstallation.user_installable.with_target(current_organization).find_by(id: params[:installation_id])
    deliver_error!(404) unless installation

    data = receive_with_openapi
    repositories = current_organization.repositories.where(name: data["repositories"])

    result = IntegrationInstallation::RepositoryEditor.perform(
      installation,
      action: :remove,
      repositories: repositories,
      editor: current_user,
      entry_point: :rest_api_enterprise_apps_remove_repository_access_to_installation
    )

    if result.success?
      deliver :enterprise_installable_organization_accessible_repositories_hash, repositories
    else
      deliver_error!(400, message: result.error)
    end
  end

  patch "/enterprises/:enterprise_id/apps/organizations/:org/installations/:installation_id/repositories", operation_id: "enterprise-apps/change-installation-repository-access-selection" do
    current_enterprise = find_enterprise!
    deliver_error!(404) unless current_enterprise&.feature_enabled?(:enterprise_app_installation_management)

    control_access :update_enterprise_organization_installation_repositories,
      resource: current_enterprise,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    current_organization = find_org!
    deliver_error!(404) unless current_organization.business == current_enterprise

    installation = IntegrationInstallation.user_installable.with_target(current_organization).find_by(id: params[:installation_id])
    deliver_error!(404) unless installation

    data = receive_with_openapi
    repositories = data["repository_selection"] == "selected" ? current_organization.repositories.where(name: data["repositories"]) : nil

    result = installation.edit(
      repositories: repositories,
      editor: current_user,
      entry_point: :rest_api_enterprise_apps_change_installation_repository_access_selection
    )

    if result.success?
      deliver :installation_hash, installation
    else
      deliver_error!(400, message: result.error)
    end
  end

  delete "/enterprises/:enterprise_id/apps/organizations/:org/installations/:installation_id", operation_id: "enterprise-apps/delete-installation" do
    current_enterprise = find_enterprise!
    deliver_error!(404) unless current_enterprise&.feature_enabled?(:enterprise_app_installation_management)

    control_access :uninstall_for_enterprise_organizations,
      resource: current_enterprise,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    current_organization = find_org!
    deliver_error!(404) unless current_organization.business == current_enterprise

    installation = IntegrationInstallation.user_installable.with_target(current_organization).find_by(id: params[:installation_id])
    deliver_error!(404) unless installation

    if installation.uninstall(actor: current_user)
      deliver_empty(status: 204)
    else
      deliver_error!(400, message: installation.errors.full_messages.join(", "))
    end
  end
end
