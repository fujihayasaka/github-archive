// Package root is the entry point to the repo-indexer command which is used to (re-)sync information to
// the `turboscan-*` Elasticsearch index and the database.
// For Elasticsearch the information is updated in two stages:
//   - repository metadata is fetched from Dotcom via the internal Twirp API and updated in the `ts_repositories` table.
//   - repository alert information is synced to Elasticsearch based on the current data in MySQL
//
// Deleted repositories on Dotcom are found via its internal repositories/audits REST API and added into `ts_deleted_repositories` table.
package root

import (
	"bytes"
	"context"
	"fmt"
	"os"
	"slices"
	"strconv"
	"strings"
	"time"

	"github.com/github/turboscan/ts/app"
	"github.com/github/turboscan/ts/transforms"

	"github.com/github/turboscan/ts/appctx"

	"github.com/spf13/cobra"

	"github.com/SamuelTissot/sqltime"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-stats"
	"github.com/github/turboscan/internal/cronjob"
	"github.com/github/turboscan/ts/gormext"
	"github.com/github/turboscan/ts/hydro/publishers"
	"github.com/github/turboscan/ts/mysql/alert"
	"github.com/github/turboscan/ts/mysql/repository"
	"github.com/pkg/errors"

	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/config"
	"github.com/github/turboscan/ts/elasticsearch"
	"github.com/github/turboscan/ts/ghapi"
	"github.com/github/turboscan/ts/twirp/clients/ghgh"
)

const (
	TargetNone   string = "none"
	TargetOldest string = "oldest"
	TargetActive string = "active"
	TargetRepo   string = "repo"
)

var allowedTargets = []string{TargetNone, TargetOldest, TargetActive, TargetRepo}

type arguments struct {
	targets            []string
	deadline           uint
	alertStep          uint
	repoStep           uint
	repoID             uint
	horizon            uint
	autoUpgrade        bool
	resetIndex         bool
	allowDelete        bool
	repoCleanup        bool
	deletedRepoCleanup bool
	skipRepoSync       bool
	skipIndexingLimits bool
}

const (
	svcName          = "repo-indexer"
	shortDescription = "is used to (re-)sync information to the `turboscan-*` Elasticsearch index and the database."
	longDescription  = `repo-indexer is used to (re-)sync information to the 'turboscan-*' Elasticsearch index and the database.
For Elasticsearch the information is updated in two stages:
	- repository metadata is fetched from Dotcom via the internal Twirp API and updated in the 'ts_repositories' table.
	- repository alert information is synced to Elasticsearch based on the current data in MySQL

Deleted repositories on Dotcom are found via its internal repositories/audits REST API and added into 'ts_deleted_repositories' table.`
)

var RepoIndexerCmd = &cobra.Command{
	Use:   svcName,
	Short: shortDescription,
	Long:  longDescription,
	RunE: func(cmd *cobra.Command, args []string) error {
		return cronjob.Execute(svcName, commandMain(cmd))
	},
}

func init() {
	RepoIndexerCmd.Flags().StringSlice("target", []string{TargetNone}, "Target repositories to index.")
	RepoIndexerCmd.Flags().Uint("deadline", 45, "Number of minutes the script is allowed to run. If specified, it will exit after that time, regardless of whether it has completed.")
	RepoIndexerCmd.Flags().Uint("repoStep", 100, "Number of repositories to update per iteration. Maximum value is 1000.")
	RepoIndexerCmd.Flags().Uint("alertStep", 1000, "Number of alerts to index per iteration.")
	RepoIndexerCmd.Flags().Uint("repoID", 0, "ID of repository to target for updating.")
	RepoIndexerCmd.Flags().Uint("horizon", 0, "Number of hours to consider as cutoff for 'oldest' and 'active' targets")
	RepoIndexerCmd.Flags().Bool("autoUpgrade", false, "Checks for index config changes and performs an index upgrade if necessary.")
	RepoIndexerCmd.Flags().Bool("resetIndex", false, "Start from scratch, deleting all data from index.")
	RepoIndexerCmd.Flags().Bool("allowDelete", false, "Delete indices after a migration")
	RepoIndexerCmd.Flags().Bool("repoCleanup", false, "Delete repositories with no analyses and no recent metadata updates.")
	RepoIndexerCmd.Flags().Bool("deletedRepoCleanup", false, "Clean up alerts related to deleted repositories.")
	RepoIndexerCmd.Flags().Bool("skipRepoSync", false, "Skip syncing repositories from the dotcom API")
	RepoIndexerCmd.Flags().Bool("skipIndexingLimits", false, "Ignore limits on the number of alerts to index per repository")
}

type skipRepoSyncAPI struct{}

func (api *skipRepoSyncAPI) GetRepositories(ctx context.Context, ids []ts.RepositoryEID) ([]*ts.Repository, error) {
	return rs.FindExisting(ctx, ids)
}

type RepoDeleter interface {
	DeletedRepositoriesOnDotcom(ctx context.Context, repoIDs []ts.RepositoryEID) (notFoundRepoIDs []ts.RepositoryEID, err error)
	InsertRepositoryForDeletion(ctx context.Context, repositoryID ts.RepositoryEID) error
}

func (api *skipRepoSyncAPI) GetReposAudits(ctx context.Context, reqData ghapi.RepoAuditsRequest) (ghapi.RepoAuditsResponse, error) {
	return reposAuditsResult(reqData.RepositoryIDs, "active"), nil
}

// limit for how many items to fetch as the repositories API times out when being called with a large set of repoIDs
const batchSizeLimit = 1000

// limit how long to spend indexing a single repository
const repoIndexingTimeout = 30 * time.Minute

var ErrDeadlineExceeded = errors.New("job deadline exceeded")
var ErrRepositoryAPIFailed = errors.New("could not fetch repository metadata from Dotcom")
var ErrAuditedRepositoryAPIFailed = errors.New("could not fetch repositories' audits from Dotcom")

var repoTwirpAPI ghgh.RepositoryAPI
var es *elasticsearch.Service
var rs *repository.Service
var as *alert.Service
var runtimeArgs []kvp.Field
var totalUpdated uint
var start time.Time
var repoDeleter RepoDeleter
var repoInternalAPI ghapi.ReposAuditsGetter

func parseArgs(cmd *cobra.Command) (*arguments, error) {
	var args arguments
	var err error
	args.targets, err = cmd.Flags().GetStringSlice("target")
	if err != nil {
		return nil, err
	}
	args.deadline, err = cmd.Flags().GetUint("deadline")
	if err != nil {
		return nil, err
	}
	args.repoStep, err = cmd.Flags().GetUint("repoStep")
	if err != nil {
		return nil, err
	}
	args.alertStep, err = cmd.Flags().GetUint("alertStep")
	if err != nil {
		return nil, err
	}
	args.repoID, err = cmd.Flags().GetUint("repoID")
	if err != nil {
		return nil, err
	}
	args.horizon, err = cmd.Flags().GetUint("horizon")
	if err != nil {
		return nil, err
	}
	args.autoUpgrade, err = cmd.Flags().GetBool("autoUpgrade")
	if err != nil {
		return nil, err
	}
	args.resetIndex, err = cmd.Flags().GetBool("resetIndex")
	if err != nil {
		return nil, err
	}
	args.allowDelete, err = cmd.Flags().GetBool("allowDelete")
	if err != nil {
		return nil, err
	}
	args.repoCleanup, err = cmd.Flags().GetBool("repoCleanup")
	if err != nil {
		return nil, err
	}
	args.deletedRepoCleanup, err = cmd.Flags().GetBool("deletedRepoCleanup")
	if err != nil {
		return nil, err
	}
	args.skipRepoSync, err = cmd.Flags().GetBool("skipRepoSync")
	if err != nil {
		return nil, err
	}
	args.skipIndexingLimits, err = cmd.Flags().GetBool("skipIndexingLimits")
	if err != nil {
		return nil, err
	}

	for _, target := range args.targets {
		if !slices.Contains(allowedTargets, target) {
			return nil, errors.New("invalid target: " + target)
		}
	}

	if slices.Contains(args.targets, TargetActive) && args.horizon == 0 {
		fmt.Fprintln(os.Stderr, "Please specify a --horizon value for the active target")
		os.Exit(1)
	}

	if slices.Contains(args.targets, TargetRepo) && args.repoID == 0 {
		fmt.Fprintln(os.Stderr, "Please specify a --repoID value for the repo target")
	}
	if !slices.Contains(args.targets, TargetRepo) && args.repoID != 0 {
		fmt.Fprintln(os.Stderr, "You have a --repoID value so you probably also meant to set a repo target")
	}

	if args.deletedRepoCleanup && args.horizon == 0 {
		fmt.Fprintln(os.Stderr, "Please specify a -horizon value for deleted repo cleanup")
		os.Exit(1)
	}

	if args.allowDelete && !args.autoUpgrade {
		fmt.Fprintln(os.Stderr, "--allowDelete only applies in the upgrade/migration scenario, so you probably want to enable --autoUpgrade as well")
		os.Exit(1)
	}

	if args.repoStep > batchSizeLimit {
		// The repositories API times out when being called with a large set of repoIDs
		fmt.Fprintf(os.Stderr, "Step value cannot be larger than %d for repository updates. Proceeding with repoStep=%d.\n", batchSizeLimit, batchSizeLimit)
		args.repoStep = batchSizeLimit
	}
	return &args, nil
}

func commandMain(cmd *cobra.Command) cronjob.JobFunc {
	return func(ctx context.Context, cfg *config.Config) error {
		cargs, err := parseArgs(cmd)
		if err != nil {
			return err
		}
		runtimeArgs = []kvp.Field{
			kvp.String("process.command", "repo-indexer"),
			kvp.String("gh.turboscan.targets", strings.Join(cargs.targets, ", ")),
			kvp.Bool("gh.turboscan.auto_upgrade", cargs.autoUpgrade),
			kvp.Int("gh.repo.id", int(cargs.repoID)),
			kvp.Uint("gh.turboscan.horizon", cargs.horizon),
			kvp.Uint("gh.turboscan.alert_step", cargs.alertStep),
			kvp.Uint("gh.turboscan.repo_step", cargs.repoStep),
			kvp.Bool("gh.turboscan.reset_index", cargs.resetIndex),
			kvp.Bool("gh.turboscan.repo_cleanup", cargs.repoCleanup),
			kvp.Bool("gh.turboscan.allow_delete", cargs.allowDelete),
			kvp.Uint("gh.turboscan.deadline", cargs.deadline),
			kvp.Bool("gh.turboscan.skip_repo_sync", cargs.skipRepoSync),
			kvp.Bool("gh.turboscan.skip_indexing_limits", cargs.skipIndexingLimits),
		}
		if err := realMain(ctx, cfg, cargs); err != nil {
			// These errors should neither log nor exit non-zero.
			if errors.Is(err, ErrDeadlineExceeded) {
				return nil
			}
			// These errors should log, but still exit non-zero, as a certain number
			// of them are "expected" in normal operation, and the system should
			// recover the next time it runs.
			reportError(ctx, err)
			if errors.Is(err, ErrRepositoryAPIFailed) {
				// This fails somewhat regularly, see https://github.com/github/code-scanning/issues/7595.
				return nil
			}
			// The returned error should be both logged, and cause the job to be considered failed.
			return err
		}
		return nil
	}
}

func realMain(ctx context.Context, cfg *config.Config, args *arguments) (err error) {
	start = time.Now()
	statsClient := appctx.Stats(ctx).WithTags(stats.Tags{"indexer": "cli", "run_targets": strings.Join(args.targets, "_")})

	ctx = appctx.WithStats(ctx, statsClient)
	logger := appctx.Logger(ctx)

	defer func() {
		statsClient.Counter("repo_indexer.updated", nil, int64(totalUpdated))
		logger.WithFields(runtimeArgs...).WithError(err).WithFields(
			kvp.Uint("gh.turboscan.total_updated", totalUpdated),
			kvp.String("gh.operation.name", "repo-indexer"),
		).Info("repo-indexer run.")
	}()

	if args.skipRepoSync {
		repoTwirpAPI = &skipRepoSyncAPI{}
		repoInternalAPI = &skipRepoSyncAPI{}
	} else {
		repoTwirpAPI, err = cfg.NewRepositoryAPI(logger, statsClient)
		if err != nil {
			return err
		}
		repoInternalAPI, err = ghapi.New(cfg, logger, statsClient)
		if err != nil {
			return err
		}
	}

	var cleaner app.Cleaner
	defer cleaner.Clean(ctx)

	db, closeDB, err := app.NewDB(ctx, cfg)
	if err != nil {
		return err
	}
	cleaner.Append(closeDB)

	rs = repository.NewService(db)

	kc, err := cfg.NewKafkaConfig(logger, statsClient)
	if err != nil {
		return err
	}
	publisher, err := publishers.New(*kc, statsClient)
	if err != nil {
		return err
	}
	cleaner.Append(publisher.Close)

	es, err = app.NewES(ctx, cfg)
	if err != nil {
		return errors.Wrap(err, "could not connect to Elasticsearch")
	}

	as, err = app.NewAlertService(db)
	repoDeleter = repository.NewDeletedRepositoryService(db, repoInternalAPI)

	err = runRepoIndexer(ctx, args)
	return err
}

func runRepoIndexer(ctx context.Context, args *arguments) (err error) {
	totalUpdated = 0
	err = es.CreateIndex(ctx, ts.Index_OrgLevel, args.resetIndex)
	if err != nil {
		return errors.Wrap(err, "could not create the org level index")
	}
	if args.autoUpgrade {
		migrationRequired, err := es.MigrationRequired(ctx, ts.Index_OrgLevel)
		if err != nil {
			return errors.Wrap(err, "could not check if index migration is required")
		}
		if migrationRequired {
			return IndexMigration(ctx, args)
		}
	}
	if args.repoCleanup {
		// We don't want to delete repos that have been updated in the last 30 days.
		cutoff := start.Add(-30 * 24 * time.Hour)
		err = CleanupDisabledRepos(ctx, cutoff, args)
		if err != nil {
			return err
		}
	}
	if args.deletedRepoCleanup {
		cutoff := start.Add(-time.Duration(args.horizon) * time.Hour)
		err = CleanupDeletedRepos(ctx, cutoff, args)
		if err != nil {
			return err
		}
	}
	if slices.Contains(args.targets, TargetActive) {
		cutoff := start.Add(-time.Duration(args.horizon) * time.Hour)
		err = SyncActiveRepos(ctx, cutoff, args)
		if err != nil {
			return err
		}
	}
	if slices.Contains(args.targets, TargetOldest) {
		cutoff := start
		if args.horizon != 0 {
			cutoff = start.Add(-time.Duration(args.horizon) * time.Hour)
		}
		err = SyncOldestRepos(ctx, cutoff, args)
		if err != nil {
			return err
		}
	}

	if slices.Contains(args.targets, TargetRepo) && args.repoID != 0 {
		repoID := ts.RepositoryEID(args.repoID)
		initial := uint(1)

		repo, err := rs.Find(ctx, repoID)
		if err != nil {
			return err
		}
		// If the repo doesnt exist we still want to update it so we create a dummy repo object
		if repo == nil {
			repo = &ts.Repository{
				RepositoryID: repoID,
			}
		}

		updated, err := syncRepositories(ctx, []*ts.Repository{repo}, args)
		logTargetCompletion(ctx, "repo", &initial, &updated, &err)()
		if err != nil {
			return err
		}
	}
	return nil
}

// IndexMigration performs a full upgrade of the Elasticsearch index.
func IndexMigration(ctx context.Context, args *arguments) error {
	migrationStartedAt, err := es.StartMigration(ctx, ts.Index_OrgLevel)
	if err != nil {
		return errors.Wrap(err, "error starting migration")
	}
	es.SetSkipMirroring(true)
	cutoff := time.Now()
	if migrationStartedAt != nil {
		cutoff = *migrationStartedAt
	}
	var initial, total uint
	defer logTargetCompletion(ctx, "migration", &initial, &total, &err)()

	initial, err = rs.CountReposToIndex(ctx, &cutoff)
	if err != nil {
		return err
	}
	for {
		repos, err := rs.ReposToIndex(ctx, &cutoff, args.repoStep)
		if err != nil {
			return err
		}
		if len(repos) == 0 {
			break
		}
		updated, err := syncRepositories(ctx, repos, args)
		total += updated
		appctx.Stats(ctx).Counter("index_stats.migrated", nil, int64(updated))
		if err != nil {
			return err
		}
	}
	es.SetSkipMirroring(false)
	// Switch the read alias to the current index and delete the old index
	return es.CompleteMigration(ctx, ts.Index_OrgLevel, args.allowDelete)
}

// SyncActiveRepos does a partial sync of the repositories that had alert updates since the cutoff time.
// By default, it only indexes the alerts that have been updated since the cutoff time.
// However, if the repository metadata is out of sync with the information in Dotcom, it reindexes the entire repository.
func SyncActiveRepos(ctx context.Context, cutoff time.Time, args *arguments) (err error) {
	var total uint
	defer logTargetCompletion(ctx, "active", nil, &total, &err)()

	statsClient := appctx.Stats(ctx)

	offset := ts.RepositoryEID(0)
	for {
		activeRepos, err := rs.ActiveRepos(gormext.WithTryReplica(ctx, true), &cutoff, offset, args.repoStep)
		if err != nil {
			return err
		}
		if len(activeRepos) == 0 {
			break
		}
		offset = activeRepos[len(activeRepos)-1]
		updated, partiallyUpdated, err := syncRepoUpdates(ctx, activeRepos, cutoff, args)
		total += updated + partiallyUpdated
		statsClient.Counter("index_stats.full_sync", nil, int64(updated))
		statsClient.Counter("index_stats.partial_sync", nil, int64(partiallyUpdated))
		if err != nil {
			return err
		}
	}
	return nil
}

// SyncOldestRepos does a full sync of the repositories that were last indexed the longest time ago.
// It batches the repos based on ascending order of the last_indexed_at time and excludes repos that have been indexed
// after the cutoff time.
func SyncOldestRepos(ctx context.Context, cutoff time.Time, args *arguments) (err error) {
	var initial, total uint
	defer logTargetCompletion(ctx, "oldest", &initial, &total, &err)()

	initial, err = rs.CountReposToIndex(gormext.WithTryReplica(ctx, true), &cutoff)
	if err != nil {
		return err
	}

	statsClient := appctx.Stats(ctx)

	for {
		oldestRepos, err := rs.ReposToIndex(gormext.WithTryReplica(ctx, true), &cutoff, args.repoStep)
		if err != nil {
			return err
		}
		if len(oldestRepos) == 0 {
			break
		}
		updated, err := syncRepositories(ctx, oldestRepos, args)
		total += updated
		statsClient.Counter("index_stats.full_sync", nil, int64(updated))
		if err != nil {
			return err
		}
	}
	return nil
}

// CleanupDisabledRepos deletes stale records from ts_repositories.
// Repos will be deleted if they never had an analysis and have not had any metadata updates in the last month.
// Records are batched based on ascending order of repository ID
func CleanupDisabledRepos(ctx context.Context, cutoff time.Time, args *arguments) (err error) {
	var total uint
	defer logTargetCompletion(ctx, "cleanup", nil, &total, &err)()

	statsClient := appctx.Stats(ctx)

	return rs.DisabledReposBatch(gormext.WithTryReplica(ctx, true), &cutoff, 10_000, func(ctx context.Context, repositoryIDs []ts.RepositoryEID) error {
		// We can get 10,000 repositories to delete in a single batch, so we will split them up into smaller batches
		// for deletion. Fetching repositories in larger batches is much cheaper than deleting them in larger batches.
		for i := 0; i < len(repositoryIDs); i += int(args.repoStep) {
			if deadlineExceeded(args) {
				return ErrDeadlineExceeded
			}

			end := i + int(args.repoStep)
			if end > len(repositoryIDs) {
				end = len(repositoryIDs)
			}

			disabledRepos := repositoryIDs[i:end]

			err := rs.Delete(ctx, disabledRepos)
			if err != nil {
				return err
			}
			statsClient.Counter("index_stats.deleted", nil, int64(len(disabledRepos)))

			total += uint(len(disabledRepos))
		}

		return nil
	})
}

// CleanupDeletedRepos cleans up alerts for repos in ts_deleted_repositories.
func CleanupDeletedRepos(ctx context.Context, cutoff time.Time, args *arguments) (err error) {
	var total uint
	defer logTargetCompletion(ctx, "deletedRepoCleanup", nil, &total, &err)()

	return rs.DeletedReposBatch(gormext.WithTryReplica(ctx, true), &cutoff, 10_000, func(ctx context.Context, repositoryIDs []ts.RepositoryEID) error {
		statsClient := appctx.Stats(ctx)
		// We can get 10,000 repositories to delete in a single batch, so we will split them up into smaller batches for deletion.
		for i := 0; i < len(repositoryIDs); i += int(args.repoStep) {
			if deadlineExceeded(args) {
				return ErrDeadlineExceeded
			}

			end := i + int(args.repoStep)
			if end > len(repositoryIDs) {
				end = len(repositoryIDs)
			}

			deletedRepos := repositoryIDs[i:end]

			timeout := time.Until(start.Add(time.Duration(args.deadline) * time.Minute))
			deletedDocs, err := es.DeleteByRepos(ctx, deletedRepos, int(timeout))
			if err != nil {
				return err
			}
			statsClient.Counter("index_stats.deleted_docs_for_deleted_repos", nil, deletedDocs)

			total += uint(len(deletedRepos))
		}

		return nil
	})
}

// syncRepositories does a full sync of the specified repositories to Elasticsearch and updates the ts_deleted_repositories table.
// For Elasticsearch, it updates the repository metadata in the db first (by fetching the latest information from Dotcom)
// and then indexes all alerts to Elasticsearch.
func syncRepositories(ctx context.Context, exitingRepos []*ts.Repository, args *arguments) (updated uint, err error) {
	repoIDs := transforms.Map(exitingRepos, func(repo *ts.Repository) ts.RepositoryEID {
		return repo.RepositoryID
	})
	repos, err := repoTwirpAPI.GetRepositories(ctx, repoIDs)
	if err != nil {
		return 0, ErrRepositoryAPIFailed
	}
	if !args.skipRepoSync {
		logDeviations(ctx, exitingRepos, repos)
	}

	err = updateReposForDeletion(ctx, repos, args)
	if err != nil {
		if errors.Is(err, ErrDeadlineExceeded) {
			return updated, ErrDeadlineExceeded
		}
		// atm we intentionally do not exist upon errors during the repos-for-deletion handling
		appctx.Logger(ctx).WithFields(runtimeArgs...).WithError(err).WithFields(kvp.Uint("gh.turboscan.total_repos", uint(len(repos)))).
			Warn("Error when syncing repositories for deletion")
	}

	indexed := []ts.RepositoryEID{}
	startedIndexingAt := sqltime.Now()
	defer func() {
		err1 := rs.SetLastIndexed(ctx, indexed, startedIndexingAt)
		if err == nil {
			// if we stopped syncing due to an error, we don't want to override it when updating the timestamp for the batch
			err = err1
		}
	}()

	for _, repo := range repos {
		if deadlineExceeded(args) {
			return updated, ErrDeadlineExceeded
		}
		err = fullRepoIndex(ctx, repo, args)
		if err != nil {
			return updated, err
		}
		indexed = append(indexed, repo.RepositoryID)
		updated++
	}
	return updated, err
}

// logDeviations compares the existing and updated repositories and logs the differences
func logDeviations(ctx context.Context, existing, updated []*ts.Repository) {
	statsClient := appctx.Stats(ctx)
	updatedByID := transforms.IndexBy(updated, func(repo *ts.Repository) ts.RepositoryEID {
		return repo.RepositoryID
	})
	for _, existingRepo := range existing {
		logger := appctx.Logger(ctx).WithFields(
			existingRepo.RepositoryID.AsKVP(),
		)
		updatedRepo := updatedByID[existingRepo.RepositoryID]
		if updatedRepo == nil {
			logger.Info("Existing repo missing update")
			continue
		}
		logger = logger.WithFields(
			kvp.Int("gh.turboscan.existing_repo.owner.id", int(existingRepo.OwnerID)),
			kvp.Int("gh.turboscan.updated_repo.owner.id", int(updatedRepo.OwnerID)),
			kvp.Bool("gh.turboscan.existing_repo.code_scanning_enabled.", existingRepo.CodeScanningEnabled),
			kvp.Bool("gh.turboscan.updated_repo.code_scanning_enabled", updatedRepo.CodeScanningEnabled),
			kvp.String("gh.turboscan.existing_repo.default_ref", string(existingRepo.DefaultRef)),
			kvp.String("gh.turboscan.updated_repo.default_ref", string(updatedRepo.DefaultRef)),
			kvp.String("gh.turboscan.existing_repo.visibility", existingRepo.Visibility.String),
			kvp.String("gh.turboscan.updated_repo.visibility", updatedRepo.Visibility.String),
			kvp.Time("gh.turboscan.existing_repo.source_updated_at", existingRepo.SourceUpdatedAt.Time),
			kvp.Time("gh.turboscan.updated_repo.source_updated_at", updatedRepo.SourceUpdatedAt.Time),
		)
		deviation := false
		// Compare the fields
		if existingRepo.CodeScanningEnabled != updatedRepo.CodeScanningEnabled {
			deviation = true
			statsClient.Counter("index_stats.deviation", stats.Tags{"type": "code_scanning_enabled"}, 1)
		}
		if !bytes.Equal(existingRepo.DefaultRef, updatedRepo.DefaultRef) {
			deviation = true
			statsClient.Counter("index_stats.deviation", stats.Tags{"type": "default_ref"}, 1)
		}
		if existingRepo.Visibility != updatedRepo.Visibility {
			deviation = true
			statsClient.Counter("index_stats.deviation", stats.Tags{"type": "visibility"}, 1)
		}
		if existingRepo.OwnerID != updatedRepo.OwnerID {
			deviation = true
			statsClient.Counter("index_stats.deviation", stats.Tags{"type": "owner_id"}, 1)
		}
		// Log the general stats
		statsClient.Counter("index_stats.repo_sync_update", stats.Tags{"deviation": strconv.FormatBool(deviation)}, 1)
		if deviation {
			logger.Info("Repository metadata deviation detected")
		}
	}
}

// syncRepoUpdates does a partial sync of the specified repositories to Elasticsearch: by default, it only
// indexes the alerts that have been updated since the cutoff time.
// However, if the repository metadata is out of sync with the information in Dotcom, it reindexes the entire repository
func syncRepoUpdates(ctx context.Context, repoIDs []ts.RepositoryEID, cutoff time.Time, args *arguments) (updated uint, partiallyUpdated uint, err error) {
	repos, err := repoTwirpAPI.GetRepositories(ctx, repoIDs)
	if err != nil {
		return 0, 0, errors.Wrap(err, "could not fetch repository metadata from Dotcom")
	}
	currentMetadata, err := rs.FindExisting(ctx, repoIDs)
	if err != nil {
		return 0, 0, errors.Wrap(err, "could not fetch repo metadata from MySQL")
	}
	metadataMap := make(map[ts.RepositoryEID]*ts.Repository)
	for _, m := range currentMetadata {
		metadataMap[m.RepositoryID] = m
	}
	indexed := []ts.RepositoryEID{}
	startedIndexingAt := sqltime.Now()
	defer func() {
		err1 := rs.SetLastIndexed(ctx, indexed, startedIndexingAt)
		if err == nil {
			// if we stopped syncing due to an error, we don't want to override it when updating the timestamp for the batch
			err = err1
		}
	}()

	for _, repo := range repos {
		if deadlineExceeded(args) {
			return updated, partiallyUpdated, ErrDeadlineExceeded
		}
		metadata := metadataMap[repo.RepositoryID]
		if repo.EqualMetadata(metadata) {
			alertCutoff := cutoff
			if metadata.LastIndexedAt.Valid && metadata.LastIndexedAt.Time.After(cutoff) {
				alertCutoff = metadata.LastIndexedAt.Time
			}
			err = indexRepository(ctx, metadata, &alertCutoff, args)
			if err != nil {
				return updated, partiallyUpdated, err
			}
			partiallyUpdated++
		} else {
			err = fullRepoIndex(ctx, repo, args)
			if err != nil {
				return updated, partiallyUpdated, err
			}
			indexed = append(indexed, repo.RepositoryID)
			updated++
		}
	}
	return updated, partiallyUpdated, err
}

// updateReposForDeletion sends the potentially deleted repositories from the API response to the /repositories/audits API, which returns only the deleted repos on Dotcon
// and inserts the purged repositories in the `ts_deleted_repositories` DB table.
func updateReposForDeletion(ctx context.Context, repos []*ts.Repository, args *arguments) error {
	logger := appctx.Logger(ctx)
	statsClient := appctx.Stats(ctx)

	logger.Info("updateReposForDeletion request",
		kvp.Int("gh.turboscan.repo.count", len(repos)),
	)

	startTime := time.Now()
	defer func() {
		statsClient.DistributionMs("repo-indexer.update_repos_for_deletion", nil, time.Since(startTime))
	}()

	// Find potentially deleted repos (missing owner or default ref can indicate a possibly purged repo)
	var deletionCandidateRepos []ts.RepositoryEID
	candidateSet := map[ts.RepositoryEID]bool{} // Used to check if there are missing data
	for _, repo := range repos {
		if repo.OwnerID == 0 || string(repo.DefaultRef) == "" {
			deletionCandidateRepos = append(deletionCandidateRepos, repo.RepositoryID)
			logger.Info("updateReposForDeletion candidate repo found",
				repo.RepositoryID.AsKVP())
			candidateSet[repo.RepositoryID] = true
		}
	}

	if len(deletionCandidateRepos) == 0 {
		return nil
	}
	statsClient.Counter("index_stats.delete_candidates", stats.Tags{}, int64(len(deletionCandidateRepos)))
	logger.Info("updateReposForDeletion candidates completed",
		kvp.Int("gh.turboscan.candidate_list_count", len(deletionCandidateRepos)),
		kvp.Int("gh.turboscan.candidate_set_count", len(candidateSet)),
	)

	// Check which repos were indeed purged on Dotcom via its internal endpoint
	deletedReposOnDotcom, err := repoDeleter.DeletedRepositoriesOnDotcom(ctx, deletionCandidateRepos)
	if err != nil {
		return err
	}

	for _, repoID := range deletedReposOnDotcom {
		if deadlineExceeded(args) {
			logger.Info("updateReposForDeletion deadline exceeded")
			return ErrDeadlineExceeded
		}

		err = repoDeleter.InsertRepositoryForDeletion(ctx, repoID)
		if err != nil {
			return errors.Wrap(err, "could not insert repo for deletion")
		}
		delete(candidateSet, repoID)
	}
	logger.Info("updateReposForDeletion audit completed",
		kvp.Int("gh.turboscan.candidate_list_count", len(deletionCandidateRepos)),
		kvp.Int("gh.turboscan.candidate_set_count", len(candidateSet)),
	)

	for missingRepo := range candidateSet {
		logger.Info("updateReposForDeletion missing candidate repo found",
			missingRepo.AsKVP())
	}

	return nil
}

// fullRepoIndex updates the repository metadata in the db and then indexes all alerts to Elasticsearch.
func fullRepoIndex(ctx context.Context, repo *ts.Repository, args *arguments) error {
	if !args.skipRepoSync {
		// update ts_repositories
		err := rs.Update(ctx, repo)
		if err != nil {
			return errors.Wrap(err, "could not update repository metadata")
		}
	}

	err := indexRepository(ctx, repo, nil, args)
	if err != nil {
		return errors.Wrap(err, "could not index repo alerts")
	}
	return nil
}

// indexRepository indexes alerts for the specified repository to Elasticsearch.
func indexRepository(ctx context.Context, repo *ts.Repository, cutoff *time.Time, args *arguments) error {
	startTime := time.Now()
	var err error
	var alertCount = 0

	logger := appctx.Logger(ctx).WithFields(
		repo.RepositoryID.AsKVP(),
		kvp.Bool("gh.turboscan.partial", cutoff != nil))

	logger.Info("Starting indexing alerts for repo")

	defer func() {
		logger.WithError(err).Info("Indexed alerts for repo",
			kvp.Float64("gh.operation.duration", float64(time.Since(startTime))),
			kvp.Int("gh.turboscan.alerts", alertCount))
	}()

	loader := as.NewLoader(repo)
	loader.SetBatchSize(int(args.alertStep))
	loader.SetCutoff(cutoff)
	loader.SetMaxTime(repoIndexingTimeout)
	if args.skipIndexingLimits {
		loader.SetMaxTime(0)
		loader.SetMaxLoad(0)
	}
	return loader.BatchedLoad(ctx, func(alerts []*ts.LogicalAlert) error {
		docs, err := ts.SearchDocumentsFromAlerts(repo, alerts)
		if err != nil {
			return err
		}
		err = es.IndexDocuments(ctx, ts.Index_OrgLevel, docs)
		if err != nil {
			return err
		}
		alertCount += len(alerts)
		logger.Info("Indexed batch of alerts",
			kvp.Int("gh.turboscan.batch", len(alerts)),
			kvp.Int("gh.turboscan.alerts", alertCount))

		return nil
	})
}

func reportError(ctx context.Context, err error, payloadFields ...kvp.Field) {
	payload := map[string]string{}
	// add all the runtime args to the payload by default
	for _, field := range runtimeArgs {
		payload[field.Key] = field.String
	}
	// add all additional fields
	for _, field := range payloadFields {
		payload[field.Key] = field.String
	}
	appctx.Report(ctx, err, payload)
}

func deadlineExceeded(args *arguments) bool {
	if args.deadline == 0 {
		return false
	}
	return time.Since(start) > time.Duration(args.deadline)*time.Minute
}

func logTargetCompletion(ctx context.Context, target string, initial *uint, total *uint, err *error) func() {
	startTime := time.Now()
	return func() {
		totalUpdated += *total
		duration := time.Since(startTime)

		fields := []kvp.Field{
			kvp.String("gh.turboscan.target", target),
			kvp.String("gh.operation.name", "repo-indexer-target-completion"),
			kvp.Float64("gh.operation.duration", float64(duration)),
			kvp.Uint("gh.turboscan.updated", *total),
		}
		if initial != nil {
			// for some of the targets, we can't get the initial count, since the query would involve
			// a cross-shard aggregation.
			fields = append(fields, kvp.Uint("gh.turboscan.initial", *initial))
			if *initial > *total {
				appctx.Stats(ctx).Counter("index_stats.remaining", stats.Tags{"target": target}, int64(*initial-*total))
			}
		}
		appctx.Logger(ctx).WithFields(fields...).WithError(*err).Info("repo-indexer: target completed")

		appctx.Stats(ctx).DistributionMs("repo_indexer.target", stats.Tags{"target": target}, duration)
	}
}

// reposAuditsResult returns a response object of the /internal/repositories/audits API - used for mocking a response/testing.
func reposAuditsResult(repoIDs []ts.RepositoryEID, status string) ghapi.RepoAuditsResponse {
	var reposAudits []ghapi.RepoAudit
	for _, repoID := range repoIDs {
		reposAudits = append(reposAudits, ghapi.RepoAudit{
			RepositoryID: repoID,
			Result:       status},
		)
	}

	return ghapi.RepoAuditsResponse{Results: reposAudits}
}
