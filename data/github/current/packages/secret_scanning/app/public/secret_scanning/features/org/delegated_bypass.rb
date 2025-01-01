# typed: strict
# frozen_string_literal: true

module SecretScanning::Features::Org
  # Organization level enablement for Delegated Bypass
  class DelegatedBypass
    extend T::Sig
    include SecretScanning::Features::FeatureFlagHelper

    CONFIG_KEY_USER_ENABLED = "secret_scanning.delegated_bypass.user_enabled"

    sig { params(org: Organization).void }
    def initialize(org)
      @org = org
      @push_protection = T.let(SecretScanning::Features::Org::PushProtection.new(@org), SecretScanning::Features::Org::PushProtection)
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
      return false unless @push_protection.feature_available?
      return false unless @org.advanced_security_purchased?
      true
    end

    # Indicate whether the feature is enabled for this organization
    sig { returns(T::Boolean) }
    def enabled?
      return false unless self.feature_available?
      @org.config.enabled?(CONFIG_KEY_USER_ENABLED)
    end
  end
end
