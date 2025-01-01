# typed: strict
# frozen_string_literal: true

module SecurityProductsEnablement::RepositorySettings
  class Manager < T::Struct
    extend T::Sig
    include GitHub::Memoizer

    const :repository, Repository
    const :actor, User
    const :data, Repositories::Settings::SecurityAnalysisEnablementFormComponent::Data
    const :cursor, T.nilable(String)
    const :custom_patterns_query, T.nilable(String)

    sig { returns(T::Array[SecurityProductsEnablement::RepositorySettings::ServiceComponent]) }
    memoize def services
      [
        self.advanced_security,
        self.dependency_graph,
        self.dependency_graph_autosubmit,
        self.secret_scanning,
        self.secret_scanning_validity_checks,
        self.secret_scanning_non_provider_patterns,
        self.secret_scanning_push_protection,
        self.security_updates,
        self.security_updates_grouping,
        self.vulnerability_alerts,
        self.private_vulnerability_reporting,
      ]
    end

    sig { returns(SecurityProductsEnablement::RepositorySettings::DependencyGraphComponent) }
    memoize def dependency_graph
      SecurityProductsEnablement::RepositorySettings::DependencyGraphComponent.new(repository, data)
    end

    sig { returns(SecurityProductsEnablement::RepositorySettings::DependencyGraphAutosubmitComponent) }
    memoize def dependency_graph_autosubmit
      SecurityProductsEnablement::RepositorySettings::DependencyGraphAutosubmitComponent.new(repository, data)
    end

    sig { returns(SecurityProductsEnablement::RepositorySettings::VulnerabilityAlertsComponent) }
    memoize def vulnerability_alerts
      SecurityProductsEnablement::RepositorySettings::VulnerabilityAlertsComponent.new(repository, data)
    end

    sig { returns(SecurityProductsEnablement::RepositorySettings::PrivateVulnerabilityReportingComponent) }
    memoize def private_vulnerability_reporting
      SecurityProductsEnablement::RepositorySettings::PrivateVulnerabilityReportingComponent.new(repository, data)
    end

    sig { returns(SecurityProductsEnablement::RepositorySettings::SecretScanningComponent) }
    memoize def secret_scanning
      SecurityProductsEnablement::RepositorySettings::SecretScanningComponent.new(repository, data, cursor, custom_patterns_query)
    end

    sig { returns(SecurityProductsEnablement::RepositorySettings::SecretScanningValidityChecksComponent) }
    memoize def secret_scanning_validity_checks
      SecurityProductsEnablement::RepositorySettings::SecretScanningValidityChecksComponent.new(repository, data)
    end

    sig { returns(SecurityProductsEnablement::RepositorySettings::SecretScanningNonProviderPatternsComponent) }
    memoize def secret_scanning_non_provider_patterns
      SecurityProductsEnablement::RepositorySettings::SecretScanningNonProviderPatternsComponent.new(repository, data)
    end

    sig { returns(SecurityProductsEnablement::RepositorySettings::SecretScanningPushProtectionComponent) }
    memoize def secret_scanning_push_protection
      SecurityProductsEnablement::RepositorySettings::SecretScanningPushProtectionComponent.new(repository, data)
    end

    sig { returns(SecurityProductsEnablement::RepositorySettings::SecurityUpdatesComponent) }
    memoize def security_updates
      SecurityProductsEnablement::RepositorySettings::SecurityUpdatesComponent.new(repository, data)
    end

    sig { returns(SecurityProductsEnablement::RepositorySettings::SecurityUpdatesGroupingComponent) }
    memoize def security_updates_grouping
      SecurityProductsEnablement::RepositorySettings::SecurityUpdatesGroupingComponent.new(repository, data)
    end

    sig { returns(SecurityProductsEnablement::RepositorySettings::AdvancedSecurityComponent) }
    memoize def advanced_security
      SecurityProductsEnablement::RepositorySettings::AdvancedSecurityComponent.new(repository, data)
    end

    sig { returns(T::Boolean) }
    memoize def has_enterprise_policy_restrictions?
      services.any?(&:restricted_by_enterprise_policy?)
    end

    sig { returns(T::Boolean) }
    memoize def has_security_configuration_restrictions?
      return false unless repository.owner&.security_configurations_enabled?

      repository_security_configuration = repository.repository_security_configuration
      repository_security_configuration&.enforced? ? services.any?(&:restricted_by_security_configuration?) : false
    end

    sig { returns(T::Boolean) }
    memoize def has_applied_security_configuration?
      return false unless repository.owner&.security_configurations_enabled?

      repository_security_configuration = repository.repository_security_configuration
      repository_security_configuration ? repository_security_configuration.applied? : false
    end

    sig { returns(T::Boolean) }
    memoize def has_mixed_restrictions?
      has_enterprise_policy_restrictions? && has_security_configuration_restrictions?
    end
  end
end
