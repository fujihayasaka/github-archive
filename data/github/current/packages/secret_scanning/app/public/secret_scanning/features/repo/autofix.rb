# typed: strict
# frozen_string_literal: true

module SecretScanning::Features::Repo
  # Repository level enablement for AI-based alert remediation and autofix
  class Autofix
    extend T::Sig
    include SecretScanning::Features::FeatureFlagHelper

    sig { params(repo: Repository).void }
    def initialize(repo)
      @repo = repo
      @public_scanning = T.let(SecretScanning::Features::Repo::PublicScanning.new(@repo), SecretScanning::Features::Repo::PublicScanning)
      @token_scanning = T.let(SecretScanning::Features::Repo::TokenScanning.new(@repo), SecretScanning::Features::Repo::TokenScanning)
    end

    # Indicate whether the feature is available for this repository
    sig { returns(T::Boolean) }
    def feature_available?
      # GHES and Proxima are not yet supported
      if GitHub.single_or_multi_tenant_enterprise?
        return false
      end

      # feature is available on public repos if public scanning is enabled, or if token scanning is enabled
      @public_scanning.enabled? || @token_scanning.enabled?
    end

    sig { returns(T::Boolean) }
    def enabled?
      self.feature_available? && feature_flag_enabled?(@repo, FeatureFlags::AUTOFIX)
    end
  end
end
