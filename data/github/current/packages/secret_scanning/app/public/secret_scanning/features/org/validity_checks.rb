# typed: strict
# frozen_string_literal: true

module SecretScanning::Features::Org
  class ValidityChecks
    include SecretScanning::Features::FeatureFlagHelper

    CONFIG_KEY_USER_ENABLED = "token_scanning_validity_checks.org.user_enabled"
    CONFIG_KEY_ENABLED_FOR_NEW_REPOS = "token_scanning_validity_checks.new_repos_enabled"

    sig { params(org: Organization).void }
    def initialize(org)
      @org = org
      @token_scanning = T.let(SecretScanning::Features::Org::TokenScanning.new(@org), SecretScanning::Features::Org::TokenScanning)
    end

    sig { returns(T::Boolean) }
    def feature_available?
      return false unless GitHub.secret_scanning_validity_checks_available_on_instance?
      return false unless feature_flag_enabled_in_hierarchy?(@org, FeatureFlags::VALIDITY_CHECKS)

      # the org should have the GHAS license
      return false unless @org.advanced_security_purchased?

      # token scanning must be available
      @token_scanning.feature_available?
    end

    sig { returns(T::Boolean) }
    def enabled?
      return false unless self.feature_available?

      return true if enabled_by_owner?

      @org.config.enabled?(CONFIG_KEY_USER_ENABLED)
    end

    sig { returns(T::Boolean) }
    def enabled_by_owner?
      return false if show_security_config_ux?
      unless @org.business.nil?
        business_validity_checks = SecretScanning::Features::Business::ValidityChecks.new(T.must(@org.business))
        return true if business_validity_checks.enabled?
      end
      false
    end

    sig { params(actor: User).void }
    def disable(actor:)
      @org.config.delete(CONFIG_KEY_USER_ENABLED, actor)
    end

    sig { params(actor: User).void }
    def enable(actor:)
      @org.config.enable(CONFIG_KEY_USER_ENABLED, actor)
    end

    # Indicates whether automatic repository opt-in is enabled for this business
    sig { returns(T::Boolean) }
    def enabled_for_new_repos?
      return false unless self.feature_available?

      @org.config.enabled?(CONFIG_KEY_ENABLED_FOR_NEW_REPOS)
    end

    # Enable automatic repository opt-in
    sig { params(actor: User).void }
    def enable_for_new_repos(actor:)
      @org.config.enable(CONFIG_KEY_ENABLED_FOR_NEW_REPOS, actor)
    end

    # Disable automatic repository opt-in
    sig { params(actor: User).void }
    def disable_for_new_repos(actor:)
      @org.config.delete(CONFIG_KEY_ENABLED_FOR_NEW_REPOS, actor)
    end

    sig { returns(T::Boolean) }
    def show_security_config_ux?
      true
    end
  end
end
