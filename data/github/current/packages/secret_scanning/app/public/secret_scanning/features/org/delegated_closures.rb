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
      true
    end

    sig { params(actor: User).returns(T::Boolean) }
    def user_can_review_closure_requests?(actor)
      return false unless self.feature_available?
      @org.has_review_delegated_alert_closure_fgp?(actor)
    end
  end
end
