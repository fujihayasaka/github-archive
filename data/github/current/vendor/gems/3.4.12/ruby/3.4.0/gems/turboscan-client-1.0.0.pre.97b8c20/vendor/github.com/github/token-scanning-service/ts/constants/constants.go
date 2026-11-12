package constants

import (
	"time"

	"github.com/github/hydro-schemas-go/hydro/schemas/github/security_center/v0/entities"
)

// NullCommitOID repesents a null commit.
const NullCommitOID = "0000000000000000000000000000000000000000"
const RefPrefix = "refs/heads/"
const MinUniqueBytesForCustomPatterns int = 1

const RepoUpdateFeature = entities.SecurityFeature_SECRET_SCANNING

// Constants for KV locks
const RenotifyLockName = "renotify"
const RenotifyLockDuration time.Duration = time.Hour

func GetDiscontinuedTokenTypes() []string {
	return []string{"NPM_TOKEN_V1_PRECISE", "FULLSTORY_API_KEY_LEGACY"}
}

// SecretScanningConfigFilePath is the path to the secret scanning config file.
const SecretScanningConfigFilePath = ".github/secret_scanning.yml" //nolint:gosec

const MaxResolutionCommentLength = 280
const MaxCustomPatternsAIGenerationInputLength = 500

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
	WikiIncrementalScanQueue           = "wikiIncrementalScan"
	HCSUpgradeBackfillQueue            = "hcsUpgradeBackfill"
	HCSUpgradePullRequestBackfillQueue = "hcsUpgradePullRequestBackfill"
	HCSUpgradeContentBackfillQueue     = "hcsUpgradeContentBackfill"
	HCSUpgradeDiscussionBackfillQueue  = "hcsUpgradeDiscussionBackfill"
	HCSUpgradeWikiBackfillQueue        = "hcsUpgradeWikiBackfill"
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
	JobGroupPreparationQueue           = "jobGroupPreparation"
	PartnerValidityCheckQueue          = "partnerValidityCheck"
	MultipartValidityCheckQueue        = "multipartValidityCheck"
	OnDemandCheckQueue                 = "onDemandValidityCheck"
	IncrGenericSecretScanQueue         = "incrGenericSecretScan"         //nolint:gosec
	IncrGenericSecretBlobDiffScanQueue = "incrGenericSecretBlobDiffScan" //nolint:gosec
	IncrGenericSecretScanSlowQueue     = "incrGenericSecretScanSlow"

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
	PublicRepoNewBranchQueue           = "freePublicRepoNewBranch"
	PublicRepoCommitQueue              = "freePublicRepoCommit"

	GenericSecretsBackfillQueue     = "genericSecretsBackfill"
	NoopBackfillQueue               = "noopBackfill"
	GenericSecretsNoopBackfillQueue = "genericSecretsNoopBackfill"

	PublishValidityEventsFeatureFlag = "secret_scanning_webhooks_include_validity"

	PublicLeakFanoutQueue   = "publicLeakFanout"
	InternalLeakFanoutQueue = "internalLeakFanout"

	AssessmentJobGroupQueue            = "assessmentJobGroup"
	AssessmentJobGroupPreparationQueue = "assessmentJobGroupPreparation"
	AssessmentGitBackfillQueue         = "assessmentGitBackfill" //nolint:gosec

	PatternConfigScanDBProcessQueue = "patternConfigScanDBProcess"
)

const (
	TombstoneRequeueIDHeader = "tombstoneRequeueIdHeader"
)

const MissingStatus = "missing status"
