// Package root is the root of the repo-deleter which deletes the related data of the repository which is permanently deleted on Dotcom
package root

import (
	"context"
	"fmt"
	"time"

	"github.com/github/turboscan/ts/app"

	"github.com/github/turboscan/ts/appctx"

	"github.com/github/turboscan/internal/cronjob"
	"github.com/github/turboscan/ts/mysql/repository"
	"github.com/spf13/cobra"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/pkg/errors"

	"github.com/github/go-stats"
	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/config"
	"github.com/github/turboscan/ts/ghapi"
)

const jobName = "turboscan-repo-deleter"

var RepoDeleterMainCmd = &cobra.Command{
	Use:   "repo-deleter",
	Short: "Command repo-deleter deletes the related data of the repository which is permanently deleted on Dotcom.",
	Long: `Command repo-deleter deletes the related data of the repository which is permanently deleted on Dotcom. This data includes:
   - Mysql: records in turboscan database tables which are attached to that repository
   - ElasticSearch: all documents with matching repository
   - Azure blob storage: SARIF files associated with the repository`,
	RunE: func(cmd *cobra.Command, args []string) error {
		return cronjob.Execute(jobName, runCmd(cmd))
	},
}

func init() {
	RepoDeleterMainCmd.Flags().Bool("delete", false, "When 'false' will only log how many repositories are eligible for deletion without doing any deletions")
	RepoDeleterMainCmd.Flags().Int("limit", 10000, "The maximum number of DB records to fetch.")
	RepoDeleterMainCmd.Flags().Uint64("repositoryID", 0, "Repository ID.")
	RepoDeleterMainCmd.Flags().Uint("deadline", 0, "Number of minutes the script is allowed to run. If specified, it will exit after that time, regardless of whether it has completed.")
}

type arguments struct {
	delete       bool
	limit        int
	repositoryID ts.RepositoryEID
	deadline     uint
}

func parseArgs(cmd *cobra.Command) (*arguments, error) {
	deleteFlag, err := cmd.Flags().GetBool("delete")
	if err != nil {
		return nil, err
	}
	limit, err := cmd.Flags().GetInt("limit")
	if err != nil {
		return nil, err
	}
	repoID, err := cmd.Flags().GetUint64("repositoryID")
	if err != nil {
		return nil, err
	}
	deadline, err := cmd.Flags().GetUint("deadline")
	if err != nil {
		return nil, err
	}
	return &arguments{
		delete:       deleteFlag,
		limit:        limit,
		repositoryID: ts.RepositoryEID(repoID),
		deadline:     deadline,
	}, err
}

// executionStoppedErr corresponds to situations where we decide to stop cleanup
// without there being an error.
// For instance if the deadline has passed or if the deletion is not safe at the moment.
var executionStoppedErr = errors.New("job stopped without error")

func runCmd(cmd *cobra.Command) cronjob.JobFunc {
	return func(ctx context.Context, cfg *config.Config) error {
		args, err := parseArgs(cmd)
		if err != nil {
			return err
		}

		var cleanup app.Cleaner
		defer cleanup.Clean(ctx)

		db, closeDB, err := app.NewDB(ctx, cfg)
		if err != nil {
			return err
		}
		cleanup.Append(closeDB)

		sarifStore, closeSarifStore, err := app.NewSarifStore(ctx, cfg)
		if err != nil {
			return err
		}
		cleanup.Append(closeSarifStore)

		es, err := app.NewES(ctx, cfg)
		if err != nil {
			return errors.Wrap(err, "could not connect to ElasticSearch")
		}

		reposAuditsAPI, err := ghapi.New(cfg, appctx.Logger(ctx), appctx.Stats(ctx))
		if err != nil {
			return errors.Wrap(err, "could not create the GitHub API client")
		}
		deletedRepoService := repository.NewDeletedRepositoryService(db, reposAuditsAPI)
		repoCleanupService := repository.NewRepositoryCleanupService(db, sarifStore, es, deletedRepoService)
		if args.deadline != 0 {
			repoCleanupService.SetDeadlineFromNow(time.Duration(args.deadline) * time.Minute)
		}
		repoDeleterCmd := newRepoDeleterCmd(deletedRepoService, repoCleanupService, *args)
		err = repoDeleterCmd.run(ctx)
		if err != nil && !errors.Is(err, executionStoppedErr) {
			return err
		}
		return nil
	}
}

type RepoDeleter interface {
	FindRepositoriesForDeletion(ctx context.Context, repoID ts.RepositoryEID, limit int) ([]*ts.DeletedRepository, error)
	DeletedRepositoriesOnDotcom(ctx context.Context, repoIDs []ts.RepositoryEID) (notFoundRepoIDs []ts.RepositoryEID, err error)
	InsertRepositoryForDeletion(ctx context.Context, repositoryID ts.RepositoryEID) error
	CompleteDeleteProgress(ctx context.Context, repositoryID ts.RepositoryEID) error
}

type RepoCleanup interface {
	DeadlineExceeded() bool
	BlobData(ctx context.Context, repositoryID ts.RepositoryEID) error
	MySQLData(ctx context.Context, repositoryID ts.RepositoryEID) error
	ElasticSearchData(ctx context.Context, repositoryID ts.RepositoryEID) error
}

type RepoDeleterCmd struct {
	service RepoDeleter
	cleanup RepoCleanup
	args    arguments
}

// newRepoDeleterCmd constructs the CLI service for deleting repositories and its associated data from turboscan
func newRepoDeleterCmd(service RepoDeleter, cleanup RepoCleanup, args arguments) *RepoDeleterCmd {

	return &RepoDeleterCmd{
		service: service,
		cleanup: cleanup,
		args:    args,
	}
}

func (r *RepoDeleterCmd) run(ctx context.Context) error {
	repos, err := r.service.FindRepositoriesForDeletion(ctx, r.args.repositoryID, r.args.limit)
	if err != nil {
		return errors.Wrap(err, "could not fetch repositories for deletion from DB")
	}

	if len(repos) == 0 {
		appctx.Logger(ctx).Info("No repositories to delete were found")
		return nil
	}

	// this is potentially a temp log until further functionality if implemented
	appctx.Logger(ctx).Info("Found repositories to be deleted", kvp.Int("gh.turboscan.total.count", len(repos)))

	// Consult the Dotcom internal API to confirm that the repo is indeed deleted
	confirmedDeletionRepoIDs, err := r.reposDeletedOnDotcom(ctx, repos)
	if err != nil {
		return errors.Wrap(err, "could not fetch repositories' audits for deletion validation from GitHub API")
	}

	for _, repo := range repos {
		if r.cleanup.DeadlineExceeded() {
			appctx.Logger(ctx).Info("Deadline exceeded - stopping execution")
			return executionStoppedErr
		}

		// Check with the fetched repoIDs from the Dotcom internal API to confirm that the repo is indeed deleted
		if _, ok := confirmedDeletionRepoIDs[repo.RepositoryID]; !ok {
			appctx.Logger(ctx).Warn(fmt.Sprintf("Skipping repo deletion as it was not marked as %s when checked against gh repositories' audit API", ghapi.RepoNotFound),
				repo.RepositoryID.AsKVP(),
			)
			appctx.Stats(ctx).Counter("repo_deleter.skipped_deletion", stats.Tags{}, 1)
			continue
		}

		if !r.args.delete {
			appctx.Logger(ctx).Info("Would have deleted but skipping due to dry-run",
				repo.RepositoryID.AsKVP(),
			)
			continue
		}

		appctx.Logger(ctx).Info("Starting deletion of repository",
			repo.RepositoryID.AsKVP(),
		)

		// We start by deleting blob data as that depends on database rows still being present
		err := r.cleanup.BlobData(ctx, repo.RepositoryID)
		if err != nil {
			if errors.Is(err, repository.ErrCleanupStopped) {
				return executionStoppedErr
			}
			appctx.Logger(ctx).WithError(err).Error("Error purging blob data for repo",
				repo.RepositoryID.AsKVP(),
			)
			appctx.Stats(ctx).Counter("repo_deleter.failed_cleanup", stats.Tags{"type": "blob"}, 1)
			continue
		}
		appctx.Stats(ctx).Counter("repo_deleter.succeeded_cleanup", stats.Tags{"type": "blob"}, 1)

		// Then we delete the MySQL data (analyses, alerts...)
		err = r.cleanup.MySQLData(ctx, repo.RepositoryID)
		if err != nil {
			if errors.Is(err, repository.ErrCleanupStopped) {
				return executionStoppedErr
			}
			appctx.Logger(ctx).WithError(err).Error("Error purging mysql data for repo",
				repo.RepositoryID.AsKVP(),
			)
			appctx.Stats(ctx).Counter("repo_deleter.failed_cleanup", stats.Tags{"type": "mysql"}, 1)
			continue
		}
		appctx.Stats(ctx).Counter("repo_deleter.succeeded_cleanup", stats.Tags{"type": "mysql"}, 1)

		// Lastly we delete the ElasticSearch data (alert-level index)
		err = r.cleanup.ElasticSearchData(ctx, repo.RepositoryID)
		if err != nil {
			if errors.Is(err, repository.ErrCleanupStopped) {
				return executionStoppedErr
			}
			appctx.Logger(ctx).WithError(err).Error("Error purging elasticsearch data for repo",
				repo.RepositoryID.AsKVP(),
			)
			appctx.Stats(ctx).Counter("repo_deleter.failed_cleanup", stats.Tags{"type": "es"}, 1)
			continue
		}
		appctx.Stats(ctx).Counter("repo_deleter.succeeded_cleanup", stats.Tags{"type": "es"}, 1)

		// If we reached here, all parts have completed and the repo can be updated as successfully deleted.
		err = r.service.CompleteDeleteProgress(ctx, repo.RepositoryID)
		if err != nil {
			appctx.Logger(ctx).WithError(err).Error("Error updating deletion completion for repo",
				repo.RepositoryID.AsKVP(),
			)
			appctx.Stats(ctx).Counter("repo_deleter.failed_cleanup", stats.Tags{"type": "complete"}, 1)
			continue
		}
		appctx.Stats(ctx).Counter("repo_deleter.completed_cleaned", stats.Tags{}, 1)
	}

	return nil
}

func (r *RepoDeleterCmd) reposDeletedOnDotcom(ctx context.Context, repoIDsToConfirm []*ts.DeletedRepository) (map[ts.RepositoryEID]bool, error) {
	var repoIDs []ts.RepositoryEID
	for _, repo := range repoIDsToConfirm {
		repoIDs = append(repoIDs, repo.RepositoryID)
	}

	deletedReposOnDotcom, err := r.service.DeletedRepositoriesOnDotcom(ctx, repoIDs)
	if err != nil {
		return nil, err
	}

	repoIDsConfirmedDeletion := make(map[ts.RepositoryEID]bool)
	for _, repoAudit := range deletedReposOnDotcom {
		repoIDsConfirmedDeletion[repoAudit] = true
	}
	return repoIDsConfirmedDeletion, nil
}
