# typed: true
# frozen_string_literal: true

# Module to share reusable code between the organization and enterprise Security Configurations controllers.
# This will be included in the Businesses::SecurityConfigurationsDependency and EnablementSettingsDependency
#
module SharedSecurityConfigurationsDependency
  extend ActiveSupport::Concern
  extend T::Helpers

  include GitHub::Memoizer

  requires_ancestor { ApplicationController }

  PERMITTED_PARAMS = %i(name description) + SecurityConfiguration::ALL_FEATURES_WITH_SKUS
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
        quickSetupHasDetailedDescription: !GitHub.enterprise?,
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
          availability: security_product_manager.dependabot_alerts_enabled? ? :available : :unavailable,
          delegated_alert_dismissal: {
            availability: security_product_manager.dependabot_delegated_alert_dismissal_enabled? ? :available : :unavailable,
          },
          malware_alerts: {
            availability: security_product_manager.dependabot_malware_alerts_enabled? ? :available : :unavailable,
          }
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
            recommended: !GitHub.single_or_multi_tenant_enterprise?,
          },
          extended_metadata: {
            availability: security_product_manager.secret_scanning_extended_metadata_enabled? ? :available : :unavailable,
            recommended: !GitHub.single_or_multi_tenant_enterprise?,
          },
        },
        private_vulnerability_reporting: {
          availability: security_product_manager.private_vulnerability_reporting_enabled? ? :available : :unavailable
        },
      },
      docsUrls: {
        aboutGHAS: DocsUrlConfig.url_for("get-started/about-github-advanced-security"),
        createConfig: DocsUrlConfig.url_for("code-security/about-security-configurations"),
        ghasBilling: DocsUrlConfig.url_for("security_products_growth/ghas-billing"),
        ghasTrial: DocsUrlConfig.url_for("security_products_growth/ghas-trial"),
        installSecurityProducts: DocsUrlConfig.url_for("security_products_growth/install-security-products"),
        userOwnedRepos: !GitHub.enterprise? ? DocsUrlConfig.url_for("security_products_growth/user-owned-repos") : nil,
        dataResidency: DocsUrlConfig.url_for("enterprises/data-stored-outside-your-region"),
      }
    }
  end

  sig { returns(T.nilable(SecurityConfiguration)) }
  memoize def github_recommended_configuration
    SecurityConfiguration.github_recommended_configuration
  end

  sig { returns(SecurityProductsEnablement::SecurityProductsManager) }
  memoize def manager
    SecurityProductsEnablement::SecurityProductsManager.new
  end

  # Builds the full advancedSecurity capability hash for a given entity (org or business).
  # Resolves the billable entity for trial lookups: for orgs, this is business || org; for businesses, it's the business itself.
  sig { params(entity: T.any(Organization, Business)).returns(T::Hash[Symbol, T.untyped]) }
  def advanced_security_capability(entity)
    billable_entity = entity.is_a?(Organization) ? (entity.business || entity) : entity
    cs_trial = ::EnterpriseCloudOnboard::CodeSecurityTrial.new(billable_entity: billable_entity)
    sp_trial = ::EnterpriseCloudOnboard::SecretProtectionTrial.new(billable_entity: billable_entity)

    if entity.is_a?(Organization)
      bundled_policy_restricted = !entity.policy_allows_advanced_security_enablement?(
        sku: Configurable::AdvancedSecurityAccessPolicy::ENTITY_ALLOWED_ALL
      )
      cs_policy_restricted = !entity.policy_allows_advanced_security_enablement?(
        sku: Configurable::AdvancedSecurityAccessPolicy::ENTITY_ALLOWED_CODE_SECURITY_ONLY
      )
      sp_policy_restricted = !entity.policy_allows_advanced_security_enablement?(
        sku: Configurable::AdvancedSecurityAccessPolicy::ENTITY_ALLOWED_SECRET_PROTECTION_ONLY
      )
    else
      bundled_policy_restricted = false
      cs_policy_restricted = false
      sp_policy_restricted = false
    end

    {
      bundled: entity.advanced_security_products_bundled?,
      bundledAdvancedSecurity: {
        orgRestrictedByEnterprisePolicy: bundled_policy_restricted,
        enablementLocked: entity.advanced_security_metered_usage_locked?,
        enablementLockReason: entity.advanced_security_metered_usage_lock_reason,
      },
      metered: entity.advanced_security_products_metered?,
      purchased: entity.advanced_security_purchased? ||
        entity.code_security_purchased? ||
        entity.secret_protection_purchased?,
      advancedSecurityEnablementLocked: entity.advanced_security_metered_usage_locked?,
      advancedSecurityEnablementLockReason: entity.advanced_security_metered_usage_lock_reason,
      codeSecurity: {
        purchased: entity.code_security_purchased?,
        enablementLocked: entity.code_security_metered_usage_locked?,
        enablementLockReason: entity.code_security_metered_usage_lock_reason,
        onTrial: cs_trial.enabled?,
        trialExpiresAt: cs_trial.enabled? ? cs_trial.expires_at.to_s : nil,
        orgRestrictedByEnterprisePolicy: cs_policy_restricted,
      },
      secretProtection: {
        purchased: entity.secret_protection_purchased?,
        enablementLocked: entity.secret_protection_metered_usage_locked?,
        enablementLockReason: entity.secret_protection_metered_usage_lock_reason,
        onTrial: sp_trial.enabled?,
        trialExpiresAt: sp_trial.enabled? ? sp_trial.expires_at.to_s : nil,
        orgRestrictedByEnterprisePolicy: sp_policy_restricted,
      },
    }
  end

  sig { params(owner: T.any(User, Business)).returns(T::Hash[String, T.untyped]) }
  def security_configuration_params(owner)
    sc_params = params.require(:security_configuration)
    sc_params.delete(:code_scanning_options) if sc_params[:code_scanning_options].nil?
    result = sc_params.permit(PERMITTED_PARAMS, PERMITTED_OPTIONS_PARAMS).to_h
    result = filter_security_scanning_generic_secrets(owner, result)
    result = filter_security_secret_scanning_extended_metadata(owner, result)
    result
  end

  sig { params(owner: T.any(User, Business), config_params: T::Hash[String, T.untyped]).returns(T::Hash[String, T.untyped]) }
  def filter_security_secret_scanning_extended_metadata(owner, config_params)
    if config_params["secret_scanning"] == "disabled" || !manager.secret_scanning_extended_metadata_enabled?
      config_params["secret_scanning_extended_metadata"] = "disabled"
    end
    config_params
  end

  sig { params(owner: T.any(User, Business), config_params: T::Hash[String, T.untyped]).returns(T::Hash[String, T.untyped]) }
  def filter_security_scanning_generic_secrets(owner, config_params)
    return config_params if owner.feature_flag_enabled?(SecretScanning::Features::FeatureFlagHelper::FeatureFlags::GENERIC_SECRETS_IN_SECURITY_CONFIGURATIONS, default: false)

    if config_params["secret_scanning"] == "disabled" || !manager.secret_scanning_generic_secrets_enabled?
      config_params["secret_scanning_generic_secrets"] = "disabled"
    else
      config_params["secret_scanning_generic_secrets"] = "not_set"
    end
    config_params
  end

  sig { params(target: T::Array[T.untyped], id: Integer).returns(SecurityConfiguration) }
  def find_security_configuration(target, id: params[:id])
    SecurityConfiguration \
      .where(target: target)
      .or(SecurityConfiguration.where(target_type: "global", target_id: 0))
      .find_by!(id: id)
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
