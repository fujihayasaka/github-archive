# typed: true
# frozen_string_literal: true

# Module to share reusable code between the organization, user, and enterprise Security Configurations controllers.
# This will be included in the Businesses::SecurityConfigurationsDependency, Users::Settings::SecurityProductsController
# and EnablementSettingsDependency
#
module SharedSecurityConfigurationsDependency
  extend ActiveSupport::Concern
  extend T::Helpers

  include GitHub::Memoizer

  requires_ancestor { ApplicationController }

  PERMITTED_PARAMS = %i(name description code_security_sku_enabled secret_protection_sku_enabled) + SecurityConfiguration::ALL_FEATURES
  # We also need to permit the parameters for any feature options that we accept as part of a configuration, so
  # we iterate over any defined feature columns and collect the parameters from the corresponding sub-class of
  # ServiceProduct::Service::Options.
  PERMITTED_OPTIONS_PARAMS = SecurityConfiguration::FEATURE_OPTIONS.each_with_object({}) do |(opts_attr, opts_class), permit|
    permit[opts_attr] = opts_class.as_params
  end

  # Default payload object that is shared between organization, user, and enterprise Security Configurations.
  # Only include data that relies on method calls which can be served by ApplicationController.
  # If you need to use current_organization, current_user, or this_business, do so in the context-specific methods.
  #
  sig { returns(T::Hash[Symbol, T.untyped]) }
  def shared_default_payload
    security_product_manager = SecurityProductsEnablement::SecurityProductsManager.new

    {
      capabilities: {
        actionsAreBilled: !GitHub.enterprise?,
        ghasFreeForPublicRepos: !GitHub.enterprise?,
        hasPublicRepos: !GitHub.multi_tenant_enterprise?,
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
        dependabot_updates: {
          availability: security_product_manager.dependabot_security_updates_enabled? ? :available : :unavailable
        },
        code_scanning: {
          availability: security_product_manager.code_scanning_default_setup_enabled? ? :available : :unavailable,
          delegated_alert_dismissal: {
            availability: security_product_manager.code_scanning_delegated_alert_dismissal_enabled? ? :available : :unavailable,
          },
          onlyLabeledRunners: GitHub.enterprise?,
        },
        secret_scanning: {
          availability: security_product_manager.secret_scanning_enabled? ? :available : :unavailable,
          validity_checks: {
            availability: security_product_manager.secret_scanning_validity_checks_enabled? ? :available : :unavailable,
          }
        },
        private_vulnerability_reporting: {
          availability: security_product_manager.private_vulnerability_reporting_enabled? ? :available : :unavailable
        },
      },
      docsUrls: {
        aboutGHAS: DocsUrlConfig.url_for("get-started/about-github-advanced-security"),
        createConfig: DocsUrlConfig.url_for("security_products_growth/create-config"),
        ghasBilling: DocsUrlConfig.url_for("security_products_growth/ghas-billing"),
        ghasTrial: DocsUrlConfig.url_for("security_products_growth/ghas-trial"),
        installSecurityProducts: DocsUrlConfig.url_for("security_products_growth/install-security-products"),
        userOwnedRepos: !GitHub.enterprise? ? DocsUrlConfig.url_for("security_products_growth/user-owned-repos") : nil,
      }
    }
  end

  sig { returns(T::Boolean) }
  def preview_next?
    current_user&.feature_enabled?(:security_configurations_preview_next)
  end

  sig { returns(T.nilable(SecurityConfiguration)) }
  memoize def github_recommended_configuration
    SecurityConfiguration.github_recommended_configuration
  end

  sig { returns(SecurityProductsEnablement::SecurityProductsManager) }
  memoize def manager
    SecurityProductsEnablement::SecurityProductsManager.new
  end

  sig { params(owner: T.any(User, Business)).returns(T::Hash[String, T.untyped]) }
  def security_configuration_params(owner)
    result = params.require(:security_configuration).permit(PERMITTED_PARAMS, PERMITTED_OPTIONS_PARAMS).to_h
    result = filter_security_scanning_generic_secrets(owner, result)
    result
  end

  sig { params(owner: T.any(User, Business), config_params: T::Hash[String, T.untyped]).returns(T::Hash[String, T.untyped]) }
  def filter_security_scanning_generic_secrets(owner, config_params)
    return config_params if owner.feature_enabled?(SecretScanning::Features::FeatureFlagHelper::FeatureFlags::GENERIC_SECRETS_IN_SECURITY_CONFIGURATIONS)

    if config_params["secret_scanning"] == "disabled" || !manager.secret_scanning_enabled?
      config_params["secret_scanning_generic_secrets"] = "disabled"
    else
      config_params["secret_scanning_generic_secrets"] = "not_set"
    end
    config_params
  end

  sig { params(target: T::Array[T.untyped]).returns(SecurityConfiguration) }
  def find_security_configuration(target)
    SecurityConfiguration \
      .where(target: target)
      .or(SecurityConfiguration.where(target_type: "global", target_id: 0))
      .find_by!(id: params[:id])
  end

  sig { params(errors: ActiveModel::Errors).returns(T::Hash[String, T::Array[String]]) }
  def serialize_errors(errors)
    {}.tap do |out|
      errors.to_hash.each do |key, values|
        nested, out[key] = values.partition { |value| value.is_a?(ActiveModel::Error) }
        nested.each do |err|
          (out["#{key}.#{err.attribute}"] ||= []) << err.message
        end
      end
    end
  end

end
