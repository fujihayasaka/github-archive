# typed: strict
# frozen_string_literal: true

module SecurityProductsEnablement::RepositorySettings
  class SecretScanningComponent < ServiceComponent # rubocop:disable ViewComponent/ComponentsHaveUnitTests
    include SecretScanning::Features::FeatureFlagHelper

    delegate :owner, to: :repository

    sig { returns(T.nilable(String)) }
    attr_reader :custom_patterns_query

    sig { returns(T.nilable(String)) }
    attr_reader :cursor

    sig { params(repository: Repository, data: Repositories::Settings::SecurityAnalysisEnablementFormComponent::Data, cursor: T.nilable(String), custom_patterns_query: T.nilable(String)).void }
    def initialize(repository, data, cursor, custom_patterns_query)
      super(repository, data)
      @repository = repository
      @cursor = cursor
      @custom_patterns_query = custom_patterns_query
    end

    sig { returns(T::Boolean) }
    def restricted?
      restricted_by_enterprise_policy? || restricted_by_security_configuration?
    end

    sig { override.returns(T::Boolean) }
    def restricted_by_enterprise_policy?
      # This checks `SecurityProduct::AdvancedSecurity` can_enable?/can_disable?
      # which will take the actor into account and allow bypasses if applicable:
      T.cast(data.secret_scanning_blocked_by_policy, T::Boolean)
    end

    sig { returns(T::Boolean) }
    def ghas_purchased
      @repository.owner&.advanced_security_purchased?
    end

    sig { override.returns(T::Boolean) }
    def restricted_by_security_configuration?
      return false unless has_enforced_security_configuration?

      @repository.security_configuration!.secret_scanning != "not_set"
    end

    sig { returns(T::Boolean) }
    def is_currently_enabled?
      data.secret_scanning_enabled
    end

    sig { returns(T::Boolean) }
    def display_shield_icon?
      return false if has_mixed_restrictions?

      restricted_by_enterprise_policy? || restricted_by_security_configuration?
    end

    sig { returns(SecretScanning::Features::Repo::ValidityChecks) }
    memoize def validity_checks
      SecretScanning::Features::Repo::ValidityChecks.new(@repository)
    end

    sig { returns(T::Boolean) }
    def validity_checks_show_new_button?
      validity_checks.show_security_config_ux?
    end

    sig { returns(SecretScanning::Features::Repo::LowerConfidencePatterns) }
    memoize def lower_confidence_patterns
      SecretScanning::Features::Repo::LowerConfidencePatterns.new(@repository)
    end

    sig { returns(T::Boolean) }
    def lower_confidence_patterns_show_new_button?
      lower_confidence_patterns.show_security_config_ux?
    end

    sig { returns(SecretScanning::Features::Repo::GenericSecrets) }
    memoize def generic_secrets
      SecretScanning::Features::Repo::GenericSecrets.new(@repository)
    end

    sig { returns(T::Boolean) }
    def generic_secrets_show_new_button?
      generic_secrets.show_security_config_ux?
    end

    sig { returns(T::Boolean) }
    def enablement_blocked?
      SecretScanning::Features::Repo::TokenScanning.new(@repository).metered_usage_locked?
    end
  end
end
