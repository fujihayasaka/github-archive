# typed: strict
# frozen_string_literal: true

module SecretScanning::Features::Business
  # Enterprise level enablement for Lower Confidence Patterns
  class LowerConfidencePatterns
    extend T::Sig
    include SecretScanning::Features::FeatureFlagHelper

    CONFIG_KEY_USER_ENABLED = "secret_scanning.lower_confidence_patterns.user_enabled"
    CONFIG_KEY_ENABLED_FOR_NEW_REPOS = "secret_scanning.lower_confidence_patterns.new_business_repos_enable"

    sig { params(business: Business).void }
    def initialize(business)
      @business = business
      @token_scanning = T.let(SecretScanning::Features::Business::TokenScanning.new(@business), SecretScanning::Features::Business::TokenScanning)
    end

    sig { params(actor: User).void }
    def disable(actor:)
      @business.config.delete(CONFIG_KEY_USER_ENABLED, actor)
    end

    sig { params(actor: User).void }
    def enable(actor:)
      @business.config.enable(CONFIG_KEY_USER_ENABLED, actor)
    end

    # Indicate whether opt-in for this feature is available for this enterprise
    sig { returns(T::Boolean) }
    def feature_available?
      return false unless @token_scanning.feature_available?
      @business.advanced_security_purchased?
    end

    # Indicate whether the feature is enabled for this enterprise
    sig { returns(T::Boolean) }
    def enabled?
      return false unless self.feature_available?
      @business.config.enabled?(CONFIG_KEY_USER_ENABLED)
    end

    # Indicate whether the feature is dark-shipped for this enterprise
    # Dark ship does not require opt-in, and the feature flag can be enabled on the repo/org/enterprise
    sig { returns(T::Boolean) }
    def dark_ship_enabled?
      return false unless @token_scanning.feature_available?
      feature_flag_enabled?(@business, FeatureFlags::LOWER_CONFIDENCE_PATTERNS_DARK_SHIP)
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
      true
    end

    sig { returns(T::Boolean) }
    def enablement_api_available?
      return false unless self.feature_available?

      feature_flag_enabled?(@business, SecretScanning::Features::FeatureFlagHelper::FeatureFlags::NON_PROVIDER_PATTERNS_ENABLEMENT_API)
    end
  end
end
