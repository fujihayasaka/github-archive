# typed: strict
# frozen_string_literal: true

module SecretScanning::Features::Business
  # Enterprise level enablement for Generic Secrets
  class GenericSecrets
    include SecretScanning::Features::FeatureFlagHelper

    CONFIG_KEY_USER_ENABLED = "secret_scanning.generic_secrets.user_enabled"
    CONFIG_KEY_ENABLED_FOR_NEW_REPOS = "secret_scanning.generic_secrets.new_business_repos_enable"

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
      true
    end

    # Indicate whether the feature is enabled for this enterprise
    sig { returns(T::Boolean) }
    def enabled?
      return false unless self.feature_available?
      @business.config.enabled?(CONFIG_KEY_USER_ENABLED)
    end

    sig { returns(T::Boolean) }
    def show_security_config_ux?
      feature_flag_enabled?(@business, FeatureFlags::GENERIC_SECRETS_IN_SECURITY_CONFIGURATIONS)
    end
  end
end
