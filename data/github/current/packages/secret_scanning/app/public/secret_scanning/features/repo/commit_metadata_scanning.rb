# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module SecretScanning::Features::Repo
  # Repository level enablement for Commit Metadata Scanning
  class CommitMetadataScanning
    extend T::Sig
    include SecretScanning::Features::FeatureFlagHelper

    sig { params(repo: Repository).void }
    def initialize(repo)
      @repo = repo
      @public_scanning = SecretScanning::Features::Repo::PublicScanning.new(@repo)
    end

    # Indicate whether the feature is available for this repository
    sig { returns(T::Boolean) }
    def feature_available?
      # Public scanning must be enabled
      @public_scanning.enabled?
    end

    # Indicate whether the feature is enabled for this repository
    sig { returns(T::Boolean) }
    def enabled?
      # Always enabled if available
      self.feature_available?
    end
  end
end
