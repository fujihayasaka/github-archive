# typed: strict
# frozen_string_literal: true

module SecretScanning::Features::Repo
  # Repository level enablement for Lower Confidence Patterns
  class LowerConfidencePatterns
    extend T::Sig
    include SecretScanning::Features::FeatureFlagHelper

    CONFIG_KEY_USER_ENABLED = "secret_scanning.lower_confidence_patterns.user_enabled"

    sig { params(repo: Repository).void }
    def initialize(repo)
      @repo = repo
      @token_scanning = T.let(SecretScanning::Features::Repo::TokenScanning.new(@repo), SecretScanning::Features::Repo::TokenScanning)
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

    # Indicate whether opt-in for this feature is available for this repository
    sig { returns(T::Boolean) }
    def feature_available?
      return false unless @token_scanning.enabled?
      # LCP is only available for GHAS repos
      SecretScanning::Features::AdvancedSecurityHelper.advanced_security_available?(@repo)
    end

    # Indicate whether the feature is enabled for this repository
    sig { returns(T::Boolean) }
    def enabled?
      return false unless self.feature_available?
      @repo.config.enabled?(CONFIG_KEY_USER_ENABLED) && @repo.config.local?(CONFIG_KEY_USER_ENABLED)
    end

    sig { returns(T::Boolean) }
    def enabled_by_organization?
      owner = @repo.owner
      return false unless owner.is_a?(Organization)
      SecretScanning::Features::Org::LowerConfidencePatterns.new(owner).enabled?
    end

    sig { returns(T::Boolean) }
    def enabled_by_enterprise?
      owner = T.must(@repo.owner)
      if owner.user?
        user_settings = SecretScanning::Features::User::LowerConfidencePatterns.new(owner)
        return user_settings.enabled_by_enterprise?
      end
      return false unless owner.is_a?(Organization)
      return false unless owner.business
      SecretScanning::Features::Business::LowerConfidencePatterns.new(T.must(owner.business)).enabled?
    end

    # Indicate whether the feature is dark-shipped for this repository
    # Dark ship does not require opt-in, and the feature flag can be enabled on the repo/org/enterprise
    sig { returns(T::Boolean) }
    def dark_ship_enabled?
      return false unless @token_scanning.enabled?
      feature_flag_enabled?(@repo, FeatureFlags::LOWER_CONFIDENCE_PATTERNS_DARK_SHIP)
    end

    sig { returns(T::Boolean) }
    def show_security_config_ux?
      true
    end

    sig { returns(T::Boolean) }
    def enablement_api_available?
      feature_flag_enabled?(@repo, SecretScanning::Features::FeatureFlagHelper::FeatureFlags::NON_PROVIDER_PATTERNS_ENABLEMENT_API)
    end
  end
end
