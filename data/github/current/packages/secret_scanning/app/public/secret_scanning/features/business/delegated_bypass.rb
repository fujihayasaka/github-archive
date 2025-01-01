# typed: strict
# frozen_string_literal: true

module SecretScanning::Features::Business
  class DelegatedBypass
    include SecretScanning::Features::FeatureFlagHelper

    sig { params(business: Business).void }
    def initialize(business)
      @business = business
      @push_protection = T.let(SecretScanning::Features::Business::PushProtection.new(@business), SecretScanning::Features::Business::PushProtection)
    end

    sig { returns(T::Boolean) }
    def feature_available?
      return false unless @push_protection.feature_available?
      @business.advanced_security_purchased?
    end

    sig { returns(T::Boolean) }
    def api_enabled?
      return false unless feature_available?
      feature_flag_enabled_in_hierarchy?(@business, FeatureFlags::ENTERPRISE_DELEGATED_BYPASS_API)
    end

    sig { returns(T::Boolean) }
    def enabled_for_security_configuration?
      return false unless feature_available?
      feature_flag_enabled_in_hierarchy?(@business, FeatureFlags::ENTERPRISE_DELEGATED_BYPASS)
    end
  end
end
