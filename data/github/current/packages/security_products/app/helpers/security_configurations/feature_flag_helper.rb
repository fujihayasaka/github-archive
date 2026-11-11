# typed: strict
# frozen_string_literal: true

module SecurityConfigurations
  class FeatureFlagHelper

    # The client-side feature flags to enable for security configurations. Used by a lot of routes so please
    # edit carefully!
    sig { returns(T::Array[Symbol]) }
    def self.client_feature_flags
      [
        SecretScanning::Features::FeatureFlagHelper::FeatureFlags::GENERIC_SECRETS_IN_SECURITY_CONFIGURATIONS,
        :ghas_config_usage_cards,
        :security_configs_quick_set_up,
        SecretScanning::Features::FeatureFlagHelper::FeatureFlags::EXTENDED_METADATA_CONFIGURABLE_IN_SECURITY_CONFIGS
      ]
    end
  end
end
