# typed: true
# frozen_string_literal: true

module SecurityProductsEnablement
  class SecurityProductsManager
    include GitHub::Memoizer

    # Output a complete list of features/services supported by SecurityConfigurations and if they are enabled.
    #
    # The output of this method is used in a couple of places:
    #   - The front-end in order to determine if we display features to users.
    #   - The back-end in order to find relevant SecurityConfigurations when a feature is toggled on the instance.
    #
    # As such, the keys returned should match the relevant DB columns because they will be used in WHERE statements!
    sig { returns(T::Hash[Symbol, T::Boolean]) }
    def services
      {
        dependency_graph: dependency_graph_enabled?,
        dependency_graph_autosubmit_action: dependency_graph_autosubmit_action_enabled?,
        dependabot_alerts: dependabot_alerts_enabled?,
        dependabot_security_updates: dependabot_security_updates_enabled?,
        code_scanning: code_scanning_default_setup_enabled?,
        code_scanning_delegated_alert_dismissal: code_scanning_delegated_alert_dismissal_enabled?,
        secret_scanning: secret_scanning_enabled?,
        secret_scanning_validity_checks: secret_scanning_validity_checks_enabled?,
        secret_scanning_push_protection: secret_scanning_enabled?,
        secret_scanning_delegated_bypass: secret_scanning_enabled?,
        secret_scanning_delegated_alert_dismissal: secret_scanning_enabled?,
        secret_scanning_non_provider_patterns: secret_scanning_enabled?,
        private_vulnerability_reporting: private_vulnerability_reporting_enabled?
      }
    end

    sig { returns(T::Array[Symbol]) }
    def disabled_services
      services.reject { |_, enabled| enabled }.keys
    end

    sig { returns(T::Boolean) }
    memoize def dependency_graph_enabled?
      GitHub.dependency_graph_enabled?
    end

    sig { returns(T::Boolean) }
    memoize def dependency_graph_autosubmit_action_enabled?
      GitHub.dependency_graph_autosubmit_action_enabled?
    end

    sig { returns(T::Boolean) }
    def dependabot_alerts_enabled?
      SecurityProduct::VulnerabilityAlerts.enabled_for_instance?
    end

    sig { returns(T::Boolean) }
    def dependabot_security_updates_enabled?
      SecurityProduct::VulnerabilityAlerts.enabled_for_instance? && GitHub.dependabot_enabled?
    end

    sig { returns(T::Boolean) }
    def code_scanning_default_setup_enabled?
      if split_sku_feature_flag_enabled?
        code_security_features_available? && GitHub.actions_enabled? && GitHub.code_scanning_enabled?
      else
        ghas_is_available? && GitHub.actions_enabled? && GitHub.code_scanning_enabled?
      end
    end

    sig { returns(T::Boolean) }
    def code_scanning_delegated_alert_dismissal_enabled?
      if split_sku_feature_flag_enabled?
        code_security_features_available? && GitHub.code_scanning_enabled?
      else
        ghas_is_available? && GitHub.code_scanning_enabled?
      end
    end

    sig { returns(T::Boolean) }
    memoize def secret_scanning_enabled?
      if split_sku_feature_flag_enabled?
        secret_protection_features_available? && GitHub.configuration_secret_scanning_enabled?
      else
        ghas_is_available? && GitHub.configuration_secret_scanning_enabled?
      end
    end

    sig { returns(T::Boolean) }
    memoize def secret_scanning_validity_checks_enabled?
      secret_scanning_enabled? && GitHub.secret_scanning_validity_checks_available_on_instance?
    end

    sig { returns(T::Boolean) }
    def private_vulnerability_reporting_enabled?
      # PVR is not supported on GitHub Enterprise Server
      GitHub.private_vulnerability_reporting_enabled?
    end

    private

    memoize def split_sku_feature_flag_enabled?
      GitHub.ghas_sku_split_enabled?
    end

    def code_security_features_available?
      # Code Security is always available unless we are on enterprise where it must be enabled in the license.
      return true if ghas_is_available?
      GitHub::Enterprise.license.code_security_enabled
    end

    def secret_protection_features_available?
      # Secret Protection is always available unless we are on enterprise where it must be enabled in the license.
      return true if ghas_is_available?
      GitHub::Enterprise.license.secret_protection_enabled
    end

    def ghas_is_available?
      # GHAS is always available unless we are on enterprise where it must be enabled in the license.
      return true unless GitHub.enterprise?
      GitHub::Enterprise.license.advanced_security_enabled
    end
  end
end
