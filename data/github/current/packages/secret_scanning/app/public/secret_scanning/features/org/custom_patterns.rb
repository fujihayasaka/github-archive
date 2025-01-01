# typed: strict
# frozen_string_literal: true

module SecretScanning::Features::Org
  # Org level enablement for Custom Pattern Scanning
  class CustomPatterns
    include SecretScanning::Features::FeatureFlagHelper

    sig { params(org: Organization).void }
    def initialize(org)
      @org = org
      @token_scanning = T.let(SecretScanning::Features::Org::TokenScanning.new(@org), SecretScanning::Features::Org::TokenScanning)
    end

    # Indicate whether the feature is available for this repository
    sig { returns(T::Boolean) }
    def feature_available?
      # the org should have the GHAS license
      return false unless @org.advanced_security_purchased?

      @token_scanning.feature_available?
    end

    sig { returns(T::Boolean) }
    def generate_expressions_with_ai_enabled?
      return false if GitHub.enterprise?
      feature_flag_enabled?(@org, FeatureFlags::CUSTOM_PATTERNS_GENERATE_REGEX_WITH_AI)
    end
  end
end
