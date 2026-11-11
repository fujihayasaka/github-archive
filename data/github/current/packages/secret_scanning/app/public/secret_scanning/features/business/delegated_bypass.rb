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
      feature_available?
    end

    sig { returns(T::Boolean) }
    def enabled_for_security_configuration?
      feature_available?
    end

    sig { returns(T::Boolean) }
    def enabled_for_entities?
      return false unless feature_available?
      return false unless enabled_for_security_configuration?
      true
    end
  end
end
