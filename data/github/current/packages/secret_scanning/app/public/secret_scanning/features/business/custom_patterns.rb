# typed: strict
# frozen_string_literal: true

module SecretScanning::Features::Business
  # Business level enablement for Custom Pattern Scanning
  class CustomPatterns
    include SecretScanning::Features::FeatureFlagHelper

    sig { params(business: Business).void }
    def initialize(business)
      @business = business
      @token_scanning = T.let(SecretScanning::Features::Business::TokenScanning.new(@business), SecretScanning::Features::Business::TokenScanning)
    end

    # Indicate whether the feature is available for this organization
    sig { returns(T::Boolean) }
    def feature_available?
      # the business should have the GHAS license
      return false unless @business.advanced_security_purchased?

      @token_scanning.feature_available?
    end

    sig { returns(T::Boolean) }
    def generate_expressions_with_ai_enabled?
      return false if GitHub.enterprise?
      feature_flag_enabled_in_hierarchy?(@business, FeatureFlags::CUSTOM_PATTERNS_GENERATE_REGEX_WITH_AI)
    end
  end
end
