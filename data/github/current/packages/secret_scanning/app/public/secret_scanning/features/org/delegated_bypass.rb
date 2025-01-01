# typed: strict
# frozen_string_literal: true

module SecretScanning::Features::Org
  # Organization level enablement for Delegated Bypass
  class DelegatedBypass
    include SecretScanning::Features::FeatureFlagHelper

    CONFIG_KEY_USER_ENABLED = "secret_scanning.delegated_bypass.user_enabled"

    sig { params(org: Organization).void }
    def initialize(org)
      @org = org
      @push_protection = T.let(SecretScanning::Features::Org::PushProtection.new(@org), SecretScanning::Features::Org::PushProtection)
    end

    # Indicate whether opt-in for this feature is available for this organization
    sig { returns(T::Boolean) }
    def feature_available?
      return false unless @push_protection.feature_available?
      return false unless @org.advanced_security_purchased?
      true
    end

    # Indicates whether the given actor is allowed to view the organization's bypass requests list
    sig { params(actor: T.nilable(User)).returns(T::Boolean) }
    def can_view_requests_list?(actor)
      return false if actor.nil?
      return false unless self.feature_available?

      @org.can_view_delegated_bypass_requests_list?(actor)
    end
  end
end
