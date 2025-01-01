# typed: strict
# frozen_string_literal: true

module SecurityConfigurations
  class FeatureFlagHelper

    # The client-side feature flags to enable for security configurations. Used by a lot of routes so please
    # edit carefully!
    sig { returns(T::Array[Symbol]) }
    def self.client_feature_flags
      [SecretScanning::Features::FeatureFlagHelper::FeatureFlags::GENERIC_SECRETS_IN_SECURITY_CONFIGURATIONS, SecretScanning::Features::FeatureFlagHelper::FeatureFlags::VALIDITY_CHECKS, SecretScanning::Features::FeatureFlagHelper::FeatureFlags::ENTERPRISE_DELEGATED_BYPASS]
    end
  end
end
