package constants

const (
	CommitMetadataScanFlag                           = "token_scanning_service_commit_metadata_scan_enabled"
	CommitCommentScanFlag                            = "token_scanning_service_commit_comment_scan_enabled"
	ContentBackfillScanFlag                          = "secret_scanning_content_backfill_scan"
	GenericSecretsScanFlag                           = "secret_scanning_generic_secrets_scan"
	GenericSecretsBlockFlag                          = "secret_scanning_generic_secrets_block"
	IngestFlag                                       = "token_scanning_service_ingest"
	LoginRevocationForCredentialInURLFlag            = "login_revocation_for_credential_in_url_enabled"
	LoginRevocationForCredentialInCommitMetadataFlag = "login_revocation_for_credential_in_commit_metadata_enabled"
	LowerConfidencePatternsDarkShipFlag              = "lower_confidence_patterns_dark_ship"
	// RepoIsAssociatedWithGithubOrMicrosoftFlag is a flag used for extra post processing behavior specific to repos owned by Microsoft (and GitHub)
	RepoIsAssociatedWithGithubOrMicrosoftFlag = "repo_is_associated_with_github_or_microsoft"
	// RepoIsPublicInGhasOrgFlag is a long lived feature flag name used for public repos in a GHAS org
	RepoIsPublicInGhasOrgFlag        = "token_scanning_service_scan_ghas_public_repos"
	UserScopedAncestorBackfillFlag   = "secret_scanning_user_scoped_ancestor_backfill"
	WikiBackfillOnPublicRepoPushFlag = "token_scanning_service_wiki_backfill_on_push"
	WikiBackfillScansFlag            = "token_scanning_service_wiki_backfill_scans"
	WikiIncrementalScansFlag         = "token_scanning_service_wiki_incremental_scans"
	WikiIncrementalScansQueueFlag    = "token_scanning_service_wiki_incremental_scans_queue"
)
