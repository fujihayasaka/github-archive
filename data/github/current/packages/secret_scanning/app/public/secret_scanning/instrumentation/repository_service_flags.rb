# typed: strict
# frozen_string_literal: true

module SecretScanning::Instrumentation
  # This class builds backend feature flags for instrumentation / service calls for Repositories
  # These flags are typically used by Token Scanning Service (TSS)
  class RepositoryServiceFlags
    include SecretScanning::Features::FeatureFlagHelper
    include GitHub::TokenScanning::TokenRevocationHelper

    sig { params(repo: Repository).void }
    def initialize(repo)
      @repo = repo
      @content_scanning = T.let(SecretScanning::Features::Repo::ContentScanning.new(@repo), SecretScanning::Features::Repo::ContentScanning)
      @commit_comment_scanning = T.let(SecretScanning::Features::Repo::CommitCommentScanning.new(@repo), SecretScanning::Features::Repo::CommitCommentScanning)
      @token_scanning = T.let(SecretScanning::Features::Repo::TokenScanning.new(@repo), SecretScanning::Features::Repo::TokenScanning)
      @public_scanning = T.let(SecretScanning::Features::Repo::PublicScanning.new(@repo), SecretScanning::Features::Repo::PublicScanning)
      @commit_metadata_scanning = T.let(SecretScanning::Features::Repo::CommitMetadataScanning.new(@repo), SecretScanning::Features::Repo::CommitMetadataScanning)
      @push_protection = T.let(SecretScanning::Features::Repo::PushProtection.new(@repo), SecretScanning::Features::Repo::PushProtection)
      @generic_secrets = T.let(SecretScanning::Features::Repo::GenericSecrets.new(@repo), SecretScanning::Features::Repo::GenericSecrets)
      @lower_confidence_patterns_scanning = T.let(SecretScanning::Features::Repo::LowerConfidencePatterns.new(@repo), SecretScanning::Features::Repo::LowerConfidencePatterns)
      @wiki_scanning = T.let(SecretScanning::Features::Repo::WikiScanning.new(@repo), SecretScanning::Features::Repo::WikiScanning)
      @capabilities = T.let(SecretScanning::Features::Repo::Capabilities.new(@repo), SecretScanning::Features::Repo::Capabilities)
    end

    # Returns Issue Scanning service flags for backend instrumentation
    sig { returns(T::Array[String]) }
    def issue_scanning_service_flags
      flags = []
      return flags unless @content_scanning.enabled?

      flags << ServiceFlags::LOGIN_REVOCATION_IN_URL

      # Repo is public and GHAS Scanning is enabled
      if @content_scanning.enabled? && @repo.public? && @capabilities.scannable? && @capabilities.ghas_secret_scanning?
        flags << ServiceFlags::TSS_SCAN_GHAS_PUBLIC_REPOS
      end

      if @lower_confidence_patterns_scanning.dark_ship_enabled?
        flags << ServiceFlags::LOWER_CONFIDENCE_PATTERNS_DARK_SHIP
      end

      flags
    end

    # Returns Group Backfill service flags for backend instrumentation
    sig { returns(T::Array[String]) }
    def group_backfill_service_flags
      flags = []
      return flags unless @content_scanning.enabled?

      flags << ServiceFlags::CONTENT_BACKFILL_SCAN

      flags
    end

    # Returns Post-receive (ie. repository push) event service flags for backend instrumentation
    sig { returns(T::Array[String]) }
    def post_receive_service_flags
      flags = []

      if self.ingest_enabled?
        flags << ServiceFlags::TOKEN_SCANNING_SERVICE_INGEST
      end

      if repo_is_associated_with_github_or_microsoft(@repo)
        flags << ServiceFlags::GH_MSFT_REPO_ASSOCIATION
      end

      # Repo is public and GHAS Scanning is enabled
      if @repo.public? && @capabilities.scannable? && @capabilities.ghas_secret_scanning?
        flags << ServiceFlags::TSS_SCAN_GHAS_PUBLIC_REPOS
      end

      if @public_scanning.enabled?
        flags << ServiceFlags::LOGIN_REVOCATION_IN_URL
      end

      flags << ServiceFlags::ALERTS_FOR_RESOLVED_BYPASS

      if @commit_metadata_scanning.enabled?
        flags << ServiceFlags::COMMIT_METADATA_SCANNING
        flags << ServiceFlags::LOGIN_REVOCATION_COMMIT_METADATA
      end

      if @token_scanning.historical_backfill_scan_enabled?
        flags << ServiceFlags::HISTORICAL_BACKFILL_SCAN
      end

      if @content_scanning.enabled?
        flags << ServiceFlags::CONTENT_BACKFILL_SCAN
      end

      if @generic_secrets.enabled?
        flags << ServiceFlags::GENERIC_SECRETS_SCAN
      end

      if @public_scanning.persist_results?
        flags << ServiceFlags::PERSIST_RESULTS_FOR_PUBLIC_REPOS
      end

      if @lower_confidence_patterns_scanning.dark_ship_enabled?
        flags << ServiceFlags::LOWER_CONFIDENCE_PATTERNS_DARK_SHIP
      end

      if @wiki_scanning.incremental_enabled?
        flags << ServiceFlags::WIKI_INCREMENTAL_SCANS
      end

      if @wiki_scanning.backfill_enabled?
        flags << ServiceFlags::WIKI_BACKFILL_SCANS
      end

      if @wiki_scanning.backfill_on_push_enabled?
        flags << ServiceFlags::WIKI_BACKFILL_ON_PUSH
      end

      if @wiki_scanning.incremental_wiki_scans_queue_enabled?
        flags << ServiceFlags::WIKI_INCREMENTAL_SCANS_QUEUE
      end

      flags
    end

    # Returns Visibility change (ex: when a repository goes from private to public) event service flags for backend instrumentation
    sig { returns(T::Array[String]) }
    def visibility_change_service_flags
      flags = []

      if self.ingest_enabled?
        flags << ServiceFlags::TOKEN_SCANNING_SERVICE_INGEST
      end

      if @lower_confidence_patterns_scanning.dark_ship_enabled?
        flags << ServiceFlags::LOWER_CONFIDENCE_PATTERNS_DARK_SHIP
      end

      flags
    end

    # Returns Discussion Scanning service flags for backend instrumentation
    sig { returns(T::Array[String]) }
    def discussion_scanning_service_flags
      flags = []
      return flags unless @content_scanning.enabled?

      flags << ServiceFlags::LOGIN_REVOCATION_IN_URL

      if @lower_confidence_patterns_scanning.dark_ship_enabled?
        flags << ServiceFlags::LOWER_CONFIDENCE_PATTERNS_DARK_SHIP
      end

      flags
    end

    # Returns Commit Comment Scanning service flags for backend instrumentation
    sig { returns(T::Array[String]) }
    def commit_comment_scanning_service_flags
      flags = []
      return flags unless @commit_comment_scanning.enabled?

      flags << ServiceFlags::COMMIT_COMMENT_SCANNING
      flags << ServiceFlags::LOGIN_REVOCATION_IN_URL

      if @lower_confidence_patterns_scanning.dark_ship_enabled?
        flags << ServiceFlags::LOWER_CONFIDENCE_PATTERNS_DARK_SHIP
      end

      flags
    end

    # Returns Pull Request Scanning service flags for backend instrumentation
    sig { returns(T::Array[String]) }
    def pull_request_scanning_service_flags
      flags = []
      return flags unless @content_scanning.enabled?

      flags << ServiceFlags::LOGIN_REVOCATION_IN_URL

      if @lower_confidence_patterns_scanning.dark_ship_enabled?
        flags << ServiceFlags::LOWER_CONFIDENCE_PATTERNS_DARK_SHIP
      end

      flags
    end

    # Returns service flags for Scans API backend service calls
    sig { returns(T::Array[String]) }
    def scans_api_service_flags
      flags = []

      if feature_flag_enabled_in_hierarchy?(@repo, SecretScanning::Features::FeatureFlagHelper::FeatureFlags::PATTERN_CONFIG)
        flags << SecretScanning::Features::FeatureFlagHelper::FeatureFlags::PATTERN_CONFIG
      end

      if @lower_confidence_patterns_scanning.dark_ship_enabled?
        flags << ServiceFlags::LOWER_CONFIDENCE_PATTERNS_DARK_SHIP
      end

      flags
    end

    sig { returns(T::Array[String]) }
    def repo_update_flags
      flags = []

      if @repo.public? && SecretScanning::Features::Repo::TokenScanning.new(@repo).feature_available?
        flags << ServiceFlags::TSS_SCAN_GHAS_PUBLIC_REPOS
      end

      if @lower_confidence_patterns_scanning.dark_ship_enabled?
        flags << ServiceFlags::LOWER_CONFIDENCE_PATTERNS_DARK_SHIP
      end

      flags
    end

    private

    sig { returns(T::Boolean) }
    def ingest_enabled?
      @token_scanning.enabled? || @public_scanning.enabled?
    end
  end
end
