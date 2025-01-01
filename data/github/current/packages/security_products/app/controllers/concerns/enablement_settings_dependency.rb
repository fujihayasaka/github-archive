# typed: true
# frozen_string_literal: true

module EnablementSettingsDependency
  extend ActiveSupport::Concern
  extend T::Sig
  extend T::Helpers
  include GitHub::Memoizer

  requires_ancestor { Orgs::Controller }

  private

  sig { returns(Hash) }
  def default_payload
    security_product_manager = SecurityProductsEnablement::SecurityProductsManager.new
    {
      organization: current_organization.display_login,
      changesInProgress: changes_in_progress,
      channel: GitHub::WebSocket::Channels.signed_security_configurations_update(current_organization),
      newRepoDefaults: security_configuration_serializer.new_repo_defaults,
      capabilities: {
        actionsAreBilled: !GitHub.enterprise?,
        ghasPurchased: current_organization.advanced_security_purchased?,
        ghasFreeForPublicRepos: !GitHub.enterprise?,
        hasPublicRepos: !GitHub.multi_tenant_enterprise?,
        hasTeams: current_organization.teams_for(current_organization).any?,
        previewNext: preview_next?,
      },
      securityProducts: {
        dependency_graph: {
          availability: security_product_manager.dependency_graph_enabled? ? :available : :unavailable,
          configurablePerRepo: !GitHub.enterprise?
        },
        dependency_graph_autosubmit_action: {
          availability: security_product_manager.dependency_graph_autosubmit_action_enabled? ? :available : :unavailable,
        },
        dependabot_alerts: {
          availability: security_product_manager.dependabot_alerts_enabled? ? :available : :unavailable
        },
        dependabot_vea: {
          availability: security_product_manager.dependabot_vea_enabled? ? :available : :unavailable
        },
        dependabot_updates: {
          availability: security_product_manager.dependabot_security_updates_enabled? ? :available : :unavailable
        },
        code_scanning: {
          availability: security_product_manager.code_scanning_default_setup_enabled? ? :available : :unavailable
        },
        secret_scanning: {
          availability: security_product_manager.secret_scanning_enabled? ? :available : :unavailable
        },
        private_vulnerability_reporting: {
          availability: security_product_manager.private_vulnerability_reporting_enabled? ? :available : :unavailable
        },
      },
      docsUrls: {
        createConfig: DocsUrlConfig.url_for("security_products_growth/create-config"),
        ghasBilling: DocsUrlConfig.url_for("security_products_growth/ghas-billing"),
        ghasTrial: DocsUrlConfig.url_for("security_products_growth/ghas-trial"),
        installSecurityProducts: DocsUrlConfig.url_for("security_products_growth/install-security-products"),
      }
    }
  end

  sig { returns(T::Boolean) }
  def preview_next?
    current_user&.feature_enabled?(:security_configurations_preview_next)
  end

  sig { returns(SecurityProductsEnablement::SecurityConfigurationSerializer) }
  memoize def security_configuration_serializer
    SecurityProductsEnablement::SecurityConfigurationSerializer.new(current_organization)
  end

  # before_action helper to return an HTTP 422 if the organization is currently applying or blocking configs.
  sig { void }
  def prevent_duplicate_enablement_events
    if current_organization.security_configurations_applying_or_blocked?
      render json: {
        error: "Another enablement event is in progress and your changes could not be saved. Please try again later."
      }, status: :unprocessable_entity
    end
  end

  def changes_in_progress
    if current_organization.jobs_in_progress?
      { inProgress: true, type: "applying_configuration" }
    elsif current_organization.security_configurations_blocked?
      { inProgress: true, type: "enablement_changes" }
    else
      { inProgress: false }
    end
  end
end
