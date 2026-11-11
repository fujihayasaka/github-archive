# typed: strict
# frozen_string_literal: true

module SecretScanning::Features::Business
  # Enterprise level enablement for Public Monitoring Alerts.
  # Gates whether an enterprise receives and can view alerts for secrets
  # authored by its members in public repositories outside the enterprise.
  #
  class PublicMonitoring
    include SecretScanning::Features::FeatureFlagHelper

    sig { params(business: Business).void }
    def initialize(business)
      @business = business
      @token_scanning = T.let(SecretScanning::Features::Business::TokenScanning.new(@business), SecretScanning::Features::Business::TokenScanning)
    end

    sig { returns(T::Boolean) }
    def feature_available?
      return false if GitHub.enterprise?
      return false unless feature_flag_enabled_in_hierarchy?(@business, FeatureFlags::PUBLIC_MONITORING_PREVIEW)
      return false unless @token_scanning.feature_available?
      return false unless @business.advanced_security_purchased? || @business.secret_protection_purchased?
      true
    end
  end
end
