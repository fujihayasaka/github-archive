# typed: strict
# frozen_string_literal: true

module SecretScanning::Features::Repo
  # Repository level enablement for Custom Pattern Scanning
  class CustomPatterns
    extend T::Sig
    include SecretScanning::Features::FeatureFlagHelper

    sig { params(repo: Repository).void }
    def initialize(repo)
      @repo = repo
      @token_scanning = T.let(SecretScanning::Features::Repo::TokenScanning.new(@repo), SecretScanning::Features::Repo::TokenScanning)
    end

    # Indicate whether the feature is available for this repository
    sig { returns(T::Boolean) }
    def feature_available?
      # the org should have the GHAS license
      return false unless @repo.owner&.advanced_security_purchased?

      @token_scanning.enabled?
    end

    sig { returns(T::Boolean) }
    def generate_expressions_with_ai_enabled?
      return false if GitHub.enterprise?
      feature_flag_enabled?(@repo, FeatureFlags::CUSTOM_PATTERNS_GENERATE_REGEX_WITH_AI)
    end
  end
end
