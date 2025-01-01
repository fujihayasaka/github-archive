# typed: strict
# frozen_string_literal: true

module SecretScanning::Features::Business
  class ValidityChecks
    extend T::Sig
    include SecretScanning::Features::FeatureFlagHelper

    CONFIG_KEY_USER_ENABLED = "token_scanning_validity_checks.business.user_enabled"
    CONFIG_KEY_ENABLED_FOR_NEW_REPOS = "token_scanning_validity_checks.new_business_repos_enable"

    sig { params(business: Business).void }
    def initialize(business)
      @business = business
      @token_scanning = T.let(SecretScanning::Features::Business::TokenScanning.new(@business), SecretScanning::Features::Business::TokenScanning)
    end

    sig { returns(T::Boolean) }
    def feature_available?
      return false if GitHub.single_or_multi_tenant_enterprise?

      # the business should have the GHAS license
      return false unless @business.advanced_security_purchased?

      # token scanning must be available
      @token_scanning.feature_available?
    end

    sig { returns(T::Boolean) }
    def enabled?
      return false unless self.feature_available?

      @business.config.enabled?(CONFIG_KEY_USER_ENABLED)
    end

    sig { params(actor: User).void }
    def disable(actor:)
      @business.config.delete(CONFIG_KEY_USER_ENABLED, actor)
    end

    sig { params(actor: User).void }
    def enable(actor:)
      @business.config.enable(CONFIG_KEY_USER_ENABLED, actor)
    end

    # Indicates whether automatic repository opt-in is enabled for this business
    sig { returns(T::Boolean) }
    def enabled_for_new_repos?
      return false unless self.feature_available?

      @business.config.enabled?(CONFIG_KEY_ENABLED_FOR_NEW_REPOS)
    end

    # Enable automatic repository opt-in
    sig { params(actor: User).void }
    def enable_for_new_repos(actor:)
      @business.config.enable(CONFIG_KEY_ENABLED_FOR_NEW_REPOS, actor)
    end

    # Disable automatic repository opt-in
    sig { params(actor: User).void }
    def disable_for_new_repos(actor:)
      @business.config.delete(CONFIG_KEY_ENABLED_FOR_NEW_REPOS, actor)
    end

    sig { returns(T::Boolean) }
    def show_security_config_ux?
      feature_flag_enabled?(@business, FeatureFlags::VALIDITY_CHECKS_IN_SECURITY_CONFIGURATIONS)
    end
  end
end
