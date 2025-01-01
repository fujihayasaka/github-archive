# typed: strict
# frozen_string_literal: true

module SecretScanning::Features::Org
  # Organization level enablement for Delegated Alert Closures
  class DelegatedClosures
    include SecretScanning::Features::FeatureFlagHelper

    CONFIG_KEY_USER_ENABLED = "secret_scanning.delegated_closures.user_enabled"

    sig { params(org: Organization).void }
    def initialize(org)
      @org = org
      @token_scanning = T.let(SecretScanning::Features::Org::TokenScanning.new(@org), SecretScanning::Features::Org::TokenScanning)
    end

    # Indicate whether opt-in for this feature is available for this organization
    sig { returns(T::Boolean) }
    def feature_available?
      return false unless @token_scanning.enabled?
      return false unless @org.advanced_security_purchased?
      # Once we remove the FF, this will just be `true`
      feature_flag_enabled?(@org, FeatureFlags::SHOW_CLOSURE_REQUESTS_ORG_SETTING)
    end

    sig { returns(T::Boolean) }
    def enabled?
      return false unless self.feature_available?
      @org.config.enabled?(CONFIG_KEY_USER_ENABLED)
    end

    sig { params(actor: User).void }
    def disable(actor:)
      @org.config.delete(CONFIG_KEY_USER_ENABLED, actor)
    end

    sig { params(actor: User).void }
    def enable(actor:)
      @org.config.enable(CONFIG_KEY_USER_ENABLED, actor)
    end
  end
end
