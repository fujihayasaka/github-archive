# typed: strict
# frozen_string_literal: true

module SecretScanning::Features::Repo
  class ValidityChecks
    extend T::Sig
    include SecretScanning::Features::FeatureFlagHelper

    CONFIG_KEY_USER_ENABLED = "token_scanning_validity_checks.repo.user_enabled"

    ENABLED_BY_BUSINESS = :business
    ENABLED_BY_ORGANIZATION = :organization
    ENABLED_BY_SELF = :self

    sig { params(repo: Repository).void }
    def initialize(repo)
      @repo = repo
      @token_scanning = T.let(SecretScanning::Features::Repo::TokenScanning.new(@repo), SecretScanning::Features::Repo::TokenScanning)
    end

    # Indicate whether the feature is available for this repository
    sig { returns(T::Boolean) }
    def feature_available?
      return false if GitHub.single_or_multi_tenant_enterprise?

      # Checks that GHAS is available for either org-owned repos or GHEC EMU repos
      # (also for GHES user-owned repos but those are out of scope for validity checks)
      return false unless SecretScanning::Features::AdvancedSecurityHelper.advanced_security_available?(@repo)

      # token scanning must be enabled
      return false unless @token_scanning.enabled?

      true
    end

    sig { returns(T::Boolean) }
    def enabled?
      return false unless feature_available?

      return true if enabled_by_org_or_biz?
      config_enabled?
    end

    sig { returns(T::Boolean) }
    def display_token_groups_validity_enabled?
      feature_flag_enabled?(@repo, SecretScanning::Features::FeatureFlagHelper::FeatureFlags::TOKEN_GROUPS_VALIDITY)
    end

    sig { returns(T::Boolean) }
    def enabled_by_org_or_biz?
      enabler = enabled_by
      enabler == ENABLED_BY_BUSINESS || enabler == ENABLED_BY_ORGANIZATION
    end

    # Returns BUSINESS if the business has enabled validity checks, ORGANIZATION if this repo's org has enabled
    # validity checks, and SELF if this repo has enabled validity checks. Returns nil otherwise
    sig { returns(T.nilable(Symbol)) }
    def enabled_by
      owner = T.must(@repo.owner)
      if owner.user?
        user_settings = SecretScanning::Features::User::ValidityChecks.new(owner)
        return ENABLED_BY_BUSINESS if user_settings.enabled_by_enterprise? && !show_security_config_ux?
        return ENABLED_BY_SELF if config_enabled?
        return nil
      end
      return nil unless owner.is_a?(Organization)
      org_settings = SecretScanning::Features::Org::ValidityChecks.new(owner)
      return ENABLED_BY_BUSINESS if org_settings.enabled_by_owner? && !show_security_config_ux?
      return ENABLED_BY_ORGANIZATION if org_settings.enabled? && !show_security_config_ux?
      return ENABLED_BY_SELF if config_enabled?
      nil
    end

    sig { params(actor: User).void }
    def disable(actor:)
      @repo.config.delete(CONFIG_KEY_USER_ENABLED, actor)
    end

    sig { params(actor: User).void }
    def enable(actor:)
      @repo.config.enable(CONFIG_KEY_USER_ENABLED, actor)
    rescue Configuration::ConflictingRecordError
      # Apparently can happen cuz of a race condition.
      # This error is rare and happens intermittently,
      # so just gonna assume it's weird user behavior and no-op.
    end

    sig { returns(T::Boolean) }
    def config_enabled?
      @repo.config.enabled?(CONFIG_KEY_USER_ENABLED)
    end

    sig { returns(T::Boolean) }
    def show_security_config_ux?
      feature_flag_enabled?(@repo, FeatureFlags::VALIDITY_CHECKS_IN_SECURITY_CONFIGURATIONS)
    end

    sig { returns(T::Boolean) }
    def on_demand_checks_enabled_for_async_token_types?
      feature_flag_enabled?(@repo, FeatureFlags::ON_DEMAND_CHECKS_ENABLED_FOR_ASYNC_TOKEN_TYPES)
    end

    sig { returns(T::Boolean) }
    def enable_with_org_or_enterprise?
      feature_flag_enabled?(@repo, FeatureFlags::VALIDITY_CHECKS_ENABLE_WITH_ORG_OR_ENTERPRISE)
    end
  end
end
