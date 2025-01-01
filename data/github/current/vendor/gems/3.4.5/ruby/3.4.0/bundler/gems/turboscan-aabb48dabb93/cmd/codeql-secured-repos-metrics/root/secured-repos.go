// Package root is the core of the codeql-secured-repos-metrics emits SLO
// metrics to datadog about whether the default setup enabled repos have
// an recent analyses within the days specified.
package root

import (
	"context"
	"fmt"
	"time"

	"github.com/github/turboscan/ts/app"

	"github.com/github/turboscan/ts/appctx"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-stats"
	"github.com/github/turboscan/internal/cronjob"
	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/config"
	"github.com/github/turboscan/ts/gormext"
	"github.com/github/turboscan/ts/hydro/publishers"
	"github.com/github/turboscan/ts/mysql/managedanalysis"
	"github.com/github/turboscan/ts/o11y"
	"github.com/github/turboscan/ts/o11y/otelgorm"
	"github.com/github/turboscan/ts/transforms"
	"github.com/jinzhu/gorm"
	"github.com/pkg/errors"
	"github.com/spf13/cobra"
)

const jobName = "turboscan-codeql-secured-repos-metrics"

var SecuredReposMetricsCMD = &cobra.Command{
	Use:   "codeql-secured-repos-metrics",
	Short: "Command codeql-secured-repos-metrics emits SLO metrics to datadog about whether the default setup enabled repos have an recent analyses within the days specified",
	Long:  `Command codeql-secured-repos-metrics emits SLO metrics to datadog about whether the default setup enabled repos have an recent analyses within the days specified.`,
	RunE: func(cmd *cobra.Command, args []string) error {
		return cronjob.Execute(jobName, runCmd(cmd))
	},
}

func runCmd(cmd *cobra.Command) cronjob.JobFunc {
	return func(ctx context.Context, cfg *config.Config) error {
		days, err := cmd.Flags().GetInt("days")
		if err != nil {
			return err
		}

		var cleaner app.Cleaner
		defer cleaner.Clean(ctx)

		db, closeDB, err := app.NewDB(ctx, cfg)
		if err != nil {
			return err
		}
		cleaner.Append(closeDB)

		// we should use the db replica when available
		ctx = gormext.WithTryReplica(ctx, true)
		db = gormext.TryGetReplica(ctx, db)

		return run(ctx, cfg, db, days, 5000)
	}
}

func run(ctx context.Context, cfg *config.Config, db *gorm.DB, days int, repoBatchSize int) error {
	var tool ts.Tool
	err := db.Model(&ts.Tool{}).Where("canonical_name = ?", "CodeQL").Limit(1).First(&tool).Error
	if err != nil {
		return errors.Wrap(err, "error fetching tool")
	}

	logger, statter := appctx.Logger(ctx), appctx.Stats(ctx)

	kc, err := cfg.NewKafkaConfig(logger, statter)
	if err != nil {
		return err
	}

	publisher, err := publishers.New(*kc, statter)
	if err != nil {
		return err
	}

	service := managedanalysis.NewService(db, publisher)
	for codeqlRepos, err := range service.IterReposRunningDefaultSetup(ctx, repoBatchSize) {
		if err != nil {
			return err
		}

		codeqlRepoIDBatches := transforms.BatchMap(codeqlRepos, 50, func(r *ts.CodeqlRepo) ts.RepositoryEID { return r.RepositoryID })
		totalBatches := len(codeqlRepoIDBatches)
		for i, batch := range codeqlRepoIDBatches {
			appctx.Logger(ctx).Info("Batch number",
				kvp.Int("gh.turboscan.secured_codeql_repos.range_min", int(codeqlRepos[0].RepositoryID)),
				kvp.Int("gh.turboscan.secured_codeql_repos.range_max", int(codeqlRepos[len(codeqlRepos)-1].RepositoryID)),
				kvp.Int("gh.turboscan.secured_codeql_repos.batch_number", i),
				kvp.Int("gh.turboscan.secured_codeql_repos.total_batches", totalBatches),
			)
			err = emitSLOs(ctx, db, tool, days, batch...)
			if err != nil {
				return err
			}
		}
	}
	return nil
}

func init() {
	SecuredReposMetricsCMD.Flags().Int("days", 8, "number of days as a threshold for emitting success or failure")
}

func emitSLOs(ctx context.Context, db *gorm.DB, tool ts.Tool, days int, repoIDs ...ts.RepositoryEID) error {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()
	db = otelgorm.SetSpanToGorm(ctx, db)

	var result []*ts.Analysis
	err := db.Model(&ts.Analysis{}).Joins(`JOIN ts_repositories ON
			ts_analyses.ref_bytes = ts_repositories.default_ref AND
			ts_analyses.repository_id = ts_repositories.repository_id`).
		Where(`ts_analyses.repository_id in (?) AND
			ts_analyses.most_recent = TRUE AND
			ts_analyses.analysis_complete = TRUE AND
			ts_analyses.tool_id = ?
			AND ts_analyses.updated_at > ?
			AND ts_analyses.source_repository_id = ts_analyses.repository_id
			AND ts_analyses.soft_deleted_at is NULL`, repoIDs, tool.ID, time.Now().Add(-time.Duration(days)*24*time.Hour)).Find(&result).Error
	if err != nil {
		return errors.Wrap(err, "error fetching analyses")
	}
	data := transforms.GroupBy(result, func(a *ts.Analysis) ts.RepositoryEID { return a.RepositoryID })
	for _, repoID := range repoIDs {
		_, ok := data[repoID]
		appctx.Stats(ctx).Counter("code_scanning.managed_analyses.weekly_run.slo", stats.Tags{
			"success": fmt.Sprintf("%t", ok),
		}, 1)
	}
	return nil
}
