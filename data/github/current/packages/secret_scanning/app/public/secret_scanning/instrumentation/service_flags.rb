# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module SecretScanning::Instrumentation
  class ServiceFlags
    ALERTS_FOR_RESOLVED_BYPASS = "alerts_for_resolved_bypass"
    COMMIT_COMMENT_SCANNING = "token_scanning_service_commit_comment_scan_enabled"
    COMMIT_METADATA_SCANNING = "token_scanning_service_commit_metadata_scan_enabled"
    DISCUSSION_SCANNING = "token_scanning_service_dicussion_scan_enabled"
    GH_MSFT_REPO_ASSOCIATION = "repo_is_associated_with_github_or_microsoft"
    LOGIN_REVOCATION_COMMIT_METADATA = "login_revocation_for_credential_in_commit_metadata_enabled"
    LOGIN_REVOCATION_IN_URL = "login_revocation_for_credential_in_url_enabled"
    PULL_REQUEST_SCANNING = "token_scanning_service_pr_scan_enabled"
    TOKEN_SCANNING_SERVICE_INGEST = "token_scanning_service_ingest"
    TSS_SCAN_GHAS_PUBLIC_REPOS = "token_scanning_service_scan_ghas_public_repos"
    CONTENT_BACKFILL_SCAN = "secret_scanning_content_backfill_scan"
    GENERIC_SECRETS_SCAN = "secret_scanning_generic_secrets_scan"
    PERSIST_RESULTS_FOR_PUBLIC_REPOS = "secret_scanning_write_results_for_public_scans"
    LOWER_CONFIDENCE_PATTERNS_DARK_SHIP = "lower_confidence_patterns_dark_ship"
    WIKI_INCREMENTAL_SCANS = "token_scanning_service_wiki_incremental_scans"
    WIKI_BACKFILL_SCANS = "token_scanning_service_wiki_backfill_scans"
    WIKI_BACKFILL_ON_PUSH = "token_scanning_service_wiki_backfill_on_push"
    WIKI_INCREMENTAL_SCANS_QUEUE = "token_scanning_service_wiki_incremental_scans_queue"
  end
end
