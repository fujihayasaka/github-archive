package constants

import (
	"time"

	"github.com/github/hydro-schemas-go/hydro/schemas/github/security_center/v0/entities"
)

// NullCommitOID repesents a null commit.
const NullCommitOID = "0000000000000000000000000000000000000000"
const RefPrefix = "refs/heads/"
const MinUniqueBytesForCustomPatterns int = 1

// RepoIsAssociatedWithGithubOrMicrosoft is a flag used for extra post processing behavior specific to repos owned by Microsoft (and GitHub)
const RepoIsAssociatedWithGithubOrMicrosoft = "repo_is_associated_with_github_or_microsoft"
const RepoUpdateFeature = entities.SecurityFeature_SECRET_SCANNING

// Constants for KV locks
const RenotifyLockName = "renotify"
const RenotifyLockDuration time.Duration = time.Hour

func GetDiscontinuedTokenTypes() []string {
	return []string{"NPM_TOKEN_V1_PRECISE", "FULLSTORY_API_KEY_LEGACY"}
}

// SecretScanningConfigFilePath is the path to the secret scanning config file.
const SecretScanningConfigFilePath = ".github/secret_scanning.yml" //nolint:gosec

// RepoIsPublicInGhasOrg is a long lived feature flag name used for public repos in a GHAS org
const RepoIsPublicInGhasOrg = "token_scanning_service_scan_ghas_public_repos"

const WriteResultsForPublicScans = "secret_scanning_write_results_for_public_scans"

const LowerConfidencePatternsDarkShip = "lower_confidence_patterns_dark_ship"

// Queues in aqueduct for jobs (NOTE: there is an initial limit of 10 queue's in aqueduct, which can be bumped - but there is always a maximum)
const (
	RepoCommitQueue                    = "repoCommit"
	RepoQueue                          = "repo"
	GistQueue                          = "gist"
	ConfigChangeQueue                  = "configAsCodeQueue"
	ZipQueue                           = "zip"
	DeadletterQueue                    = "deadletter"
	BackfillQueue                      = "backfill"
	ContentBackfillQueue               = "contentBackfill"
	PullRequestBackfillQueue           = "pullRequestBackfill"
	DiscussionBackfillQueue            = "discussionBackfill"
	WikiBackfillQueue                  = "wikiBackfill"
	HCSUpgradeBackfillQueue            = "hcsUpgradeBackfill"
	HCSUpgradePullRequestBackfillQueue = "hcsUpgradePullRequestBackfill"
	HCSUpgradeContentBackfillQueue     = "hcsUpgradeContentBackfill"
	HCSUpgradeDiscussionBackfillQueue  = "hcsUpgradeDiscussionBackfill"
	CustomPatternBackfillQueue         = "customPatternBackfill"
	CustomPatternUpdateQueue           = "customPatternUpdate"
	DependabotPRQueue                  = "dependabot"
	CommitMetadataQueue                = "commitMetadata"
	// The DryRunQueueV2 is specifically for running dryRun jobs
	// the DryRunJobGroupQueue is a jobGroup job and manages related dryRun jobs in parallel
	// Has a backing record in the DB, and deals with concurrency
	DryRunQueueV2       = "dryRunV2"
	DryRunJobGroupQueue = "dryRunJobGroup"
	JobGroupQueue       = "jobGroup"

	// JobGroupPreparationQueue is used for the JobGroupPreparationJob which ensures the `secret_scanning_scans` table
	// has db records for every scan that needs to happen for a given job group. once this is ensured, that job will
	// enqueue the related job group for processing.
	JobGroupPreparationQueue    = "jobGroupPreparation"
	PartnerValidityCheckQueue   = "partnerValidityCheck"
	MultipartValidityCheckQueue = "multipartValidityCheck"
	OnDemandCheckQueue          = "onDemandValidityCheck"
	IncrGenericSecretScanQueue  = "incrGenericSecretScan" //nolint:gosec

	IssueScanQueue             = "issue_scan"
	IssueCommentScanQueue      = "issue_comment_scan"
	PullRequestScan            = "pull_request_scan"
	PullRequestCommentScan     = "pull_request_comment_scan"
	DiscussionScanQueue        = "discussion_scan"
	DiscussionCommentScanQueue = "discussion_comment_scan"

	CommitCommentCreateQueue = "commit_comment_create"
	CommitCommentUpdateQueue = "commit_comment_update"

	NPMPublishQueue = "npm_publish"

	RepoSyncQueue = "repo_sync"

	PublicRepoJobGroupQueue            = "publicRepoJobGroup"
	PublicRepoJobGroupPreparationQueue = "publicRepoJobGroupPreparation"
	PublicRepoBackfillQueue            = "publicRepoBackfill"

	GenericSecretsBackfillQueue = "genericSecretsBackfill"
	NoopBackfillQueue           = "noopBackfill"

	PublishValidityEventsFeatureFlag = "secret_scanning_webhooks_include_validity"

	ExposureFanoutQueue = "exposureFanout"
)
