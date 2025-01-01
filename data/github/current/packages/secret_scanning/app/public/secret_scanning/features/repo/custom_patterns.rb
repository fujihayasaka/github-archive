# typed: strict
# frozen_string_literal: true

module SecretScanning::Features::Repo
  # Repository level enablement for Custom Pattern Scanning
  class CustomPatterns
    include SecretScanning::Features::FeatureFlagHelper

    sig { params(repo: Repository).void }
    def initialize(repo)
      @repo = repo
      @token_scanning = T.let(SecretScanning::Features::Repo::TokenScanning.new(@repo), SecretScanning::Features::Repo::TokenScanning)
    end

    # Indicate whether the feature is available for this repository
    sig { returns(T::Boolean) }
    def feature_available?
      # the org should have secret scanning available via GHAS or GHSP
      return false unless SecretScanning::Features::AdvancedSecurityHelper.secret_scanning_available?(@repo)

      @token_scanning.enabled?
    end

    sig { returns(T::Boolean) }
    def generate_expressions_with_ai_enabled?
      return false if GitHub.enterprise?
      true
    end
  end
end
