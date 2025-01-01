# typed: strict
# frozen_string_literal: true

module SecretScanning::Features::Business
  # Enterprise level enablement for Generic Secrets
  class GenericSecrets
    extend T::Sig
    include SecretScanning::Features::FeatureFlagHelper

    CONFIG_KEY_USER_ENABLED = "secret_scanning.generic_secrets.user_enabled"

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
      return false if GitHub.enterprise?
      return false unless @token_scanning.feature_available?
      return false unless @business.advanced_security_purchased?
      feature_flag_enabled?(@business, FeatureFlags::GENERIC_SECRETS_SCAN) && feature_flag_enabled?(@business, FeatureFlags::GENERIC_SECRETS_OWNER_ENABLEMENT)
    end

    # Indicate whether the feature is enabled for this enterprise
    sig { returns(T::Boolean) }
    def enabled?
      return false unless self.feature_available?
      @business.config.enabled?(CONFIG_KEY_USER_ENABLED)
    end

    # Indicate whether the enterprise policy can be set for this business
    sig { returns(T::Boolean) }
    def policy_available?
      feature_flag_enabled?(@business, FeatureFlags::GENERIC_SECRETS_ENTERPRISE_POLICY)
    end
  end
end
