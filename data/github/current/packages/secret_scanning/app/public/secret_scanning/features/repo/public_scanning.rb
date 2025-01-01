# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module SecretScanning::Features::Repo
  # Public Scanning feature
  #
  # We currently distinguish 2 branches of Secret Scanning:
  #
  # [Public scans]
  # - Included and mandatory for ALL public repos no matter their ownership or licensing
  # - Includes automatic revocation of github and partner tokens
  #
  # [GHAS scans]
  # - Only available to repos part of a GHAS organization/enterprise
  # - Includes the full Secret Scanning user experience
  # - Available to repos of any visibility (Public, Internal, Private), including archived repos.
  #
  # As a result, public repos can currently benefit from both types of scans if they are also part of a GHAS org.
  #
  # This feature class focuses on Public Scanning
  class PublicScanning
    include SecretScanning::Features::FeatureFlagHelper

    sig { params(repo: Repository).void }
    def initialize(repo)
      @repo = repo
      @token_scanning = SecretScanning::Features::Repo::TokenScanning.new(repo)
    end

    # Indicates whether the Public Scanning feature as a whole is available to the current repository
    sig { returns(T::Boolean) }
    def feature_available?
      self.base_feature_available? && !@token_scanning.staff_locked?
    end

    # Indicates whether Public Scanning is enabled for the current repository
    sig { returns(T::Boolean) }
    def enabled?
      # base feature must be available but otherwise it's always enabled
      self.feature_available?
    end

    # Indicates whether the feature is available to administer in stafftools
    # This is exposed separately because most other enablement methods need to check for staff locks
    sig { returns(T::Boolean) }
    def stafftools_available?
      self.base_feature_available?
    end

    # Indicate whether the service should persist token scan results for the repo
    sig { returns(T::Boolean) }
    def persist_results?
      return false unless self.enabled?
      feature_flag_enabled?(@repo, FeatureFlags::PERSIST_RESULTS_FOR_PUBLIC_REPOS)
    end

    private

    # Base feature availability checks
    sig { returns(T::Boolean) }
    def base_feature_available?
      # not supported on GHES
      return false if GitHub.enterprise?

      # global config check
      # should be on by default for dotcom and needs to be enabled for enterprise
      return false unless GitHub.configuration_secret_scanning_enabled?

      # only supported for public repos
      @repo.public?
    end
  end
end
