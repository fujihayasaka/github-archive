# typed: strict
# frozen_string_literal: true

module SecretScanning::Features::Org
  # Organization level enablement for Lower Confidence Patterns
  class LowerConfidencePatterns
    extend T::Sig
    include SecretScanning::Features::FeatureFlagHelper

    CONFIG_KEY_USER_ENABLED = "secret_scanning.lower_confidence_patterns.user_enabled"
    CONFIG_KEY_ENABLED_FOR_NEW_REPOS = "secret_scanning.lower_confidence_patterns.new_repos_enable"

    sig { params(org: Organization).void }
    def initialize(org)
      @org = org
      @token_scanning = T.let(SecretScanning::Features::Org::TokenScanning.new(@org), SecretScanning::Features::Org::TokenScanning)
    end

    sig { params(actor: User).void }
    def disable(actor:)
      @org.config.delete(CONFIG_KEY_USER_ENABLED, actor)
    end

    sig { params(actor: User).void }
    def enable(actor:)
      @org.config.enable(CONFIG_KEY_USER_ENABLED, actor)
    end

    # Indicate whether opt-in for this feature is available for this organization
    sig { returns(T::Boolean) }
    def feature_available?
      return false unless @token_scanning.feature_available?
      @org.advanced_security_purchased?
    end

    # Indicate whether the feature is enabled for this organization
    sig { returns(T::Boolean) }
    def enabled?
      return false unless self.feature_available?
      return true if self.enabled_by_enterprise?
      @org.config.enabled?(CONFIG_KEY_USER_ENABLED)
    end

    sig { returns(T::Boolean) }
    def enabled_by_enterprise?
      return false if show_security_config_ux?
      return false unless @org.business
      SecretScanning::Features::Business::LowerConfidencePatterns.new(T.must(@org.business)).enabled?
    end

    # Indicate whether the feature is dark-shipped for this organization
    # Dark ship does not require opt-in, and the feature flag can be enabled on the repo/org/enterprise
    sig { returns(T::Boolean) }
    def dark_ship_enabled?
      return false unless @token_scanning.feature_available?
      feature_flag_enabled?(@org, FeatureFlags::LOWER_CONFIDENCE_PATTERNS_DARK_SHIP)
    end

    sig { returns(T::Boolean) }
    def enabled_by_owner?
      return false if show_security_config_ux?
      return false unless @org.business
      SecretScanning::Features::Business::LowerConfidencePatterns.new(T.must(@org.business)).enabled?
    end

    sig { returns(T::Boolean) }
    def show_security_config_ux?
      true
    end

    sig { returns(T::Boolean) }
    def enable_with_org_or_enterprise?
      true
    end

    # Indicates whether automatic repository opt-in is enabled for this business
    sig { returns(T::Boolean) }
    def enabled_for_new_repos?
      false
    end
  end
end
