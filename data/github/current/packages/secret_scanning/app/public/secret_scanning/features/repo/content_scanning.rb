# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module SecretScanning::Features::Repo
  # Repository level enablement for Content Scanning
  class ContentScanning
    include SecretScanning::Features::FeatureFlagHelper

    sig { params(repo: Repository).void }
    def initialize(repo)
      @repo = repo
      @public_scanning = SecretScanning::Features::Repo::PublicScanning.new(@repo)
      @token_scanning = SecretScanning::Features::Repo::TokenScanning.new(@repo)
    end

    # Indicate whether the feature is available for this repository
    sig { returns(T::Boolean) }
    def feature_available?
      if GitHub.enterprise?
        return false unless GitHub.secret_scanning_for_all_content_types_enabled?
      end

      # feature is available on public repos if public scanning is enabled, or if token scanning is enabled
      @public_scanning.enabled? || @token_scanning.enabled?
    end

    # Indicate whether the feature is enabled for this repository
    sig { returns(T::Boolean) }
    def enabled?
      # Always enabled if available
      self.feature_available?
    end
  end
end
