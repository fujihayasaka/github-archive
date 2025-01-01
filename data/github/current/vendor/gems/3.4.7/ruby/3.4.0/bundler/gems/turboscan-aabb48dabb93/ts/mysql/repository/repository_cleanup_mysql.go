// this file adds additional functions on RepositoryCleanupService
// to handle deletion of MySQL data for a repository.

package repository

import (
	"context"
	"time"

	"github.com/github/turboscan/ts/appctx"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-stats"
	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/o11y"
	"github.com/github/turboscan/ts/o11y/otelgorm"
	"github.com/pkg/errors"
)

// TablesToDelete lists all the tables we want to delete repository data
// from. They are assumed to have an `id` field and a `repository_id` field
func TablesToDelete() []string {
	return []string{
		"ts_alert_links",
		"ts_analysis_rules",
		"ts_analysis_query_suites",
		"ts_analysis_tool_versions",
		"ts_analyses",
		"ts_analysis_extracted_files",
		"ts_analysis_extracted_files_messages",
		"ts_analysis_messages",
		"ts_code_flows_documents",
		"ts_codeql_configs",
		"ts_codeql_repos",
		"ts_codeql_runs",
		"ts_codeql_schedules",
		"ts_configurations",
		"ts_deliveries",
		"ts_logical_alerts",
		"ts_physical_alerts",
		"ts_process_errors",
		"ts_published_enabled_states",
		"ts_related_locations",
		"ts_repositories",
		"ts_security_campaign_alerts",
		"ts_snippets",
		"ts_timeline_events",
		"ts_suggested_fix_files",
		"ts_suggested_fix_alerts",
		"ts_suggested_fixes",
		ts.LogicalAlertsSeqTableName,
	}
}

// AlertTablesToDelete lists all the tables that reference alert data. They are used by the alert-cleaner command.
func AlertTablesToDelete() []string {
	return []string{
		"ts_alert_links",
		"ts_code_flows_documents",
		"ts_physical_alerts",
		"ts_related_locations",
		"ts_security_campaign_alerts",
		"ts_snippets",
		"ts_timeline_events",
		"ts_suggested_fix_files",
		"ts_suggested_fix_alerts",
		"ts_suggested_fixes",
		"ts_logical_alerts", // IMPORTANT: this needs to be the last table in the list as it is the one we use to enforce alert limits.
	}
}

type contextKey string

var cleanupBatchSizeKey contextKey = "cleanup-batch-size"

// WithMySQLDataBatchSize overrides the default number of analyses to process in one batch when calling MySQLData
func WithMySQLDataBatchSize(ctx context.Context, mysqlCleanupBatchSize int) context.Context {
	return context.WithValue(ctx, cleanupBatchSizeKey, mysqlCleanupBatchSize)
}

// MySQLData deletes all data for a repository from MySQL.
func (s *RepositoryCleanupService) MySQLData(ctx context.Context, repositoryID ts.RepositoryEID) error {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()

	// Number of analyses to process in one batch
	mysqlCleanupBatchSize := 1000
	if v, ok := ctx.Value(cleanupBatchSizeKey).(int); ok {
		mysqlCleanupBatchSize = v
	}

	var err error
	startTime := time.Now()
	defer func() {
		appctx.Stats(ctx).DistributionMs("repo_cleanup.mysql_data", nil, time.Since(startTime))
		appctx.Logger(ctx).WithError(err).Info("MySQLData request",
			kvp.Float64("gh.operation.duration", float64(time.Since(startTime))),
			repositoryID.AsKVP(),
		)
	}()

	for _, table := range TablesToDelete() {
		err := s.deleteTableByRepoID(ctx, repositoryID, table, mysqlCleanupBatchSize)
		if err != nil {
			return err
		}
	}
	return nil
}

// AlertData deletes all alert data for a repository from MySQL.
func (s *RepositoryCleanupService) AlertData(ctx context.Context, repositoryID ts.RepositoryEID) error {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()

	// Number of analyses to process in one batch
	mysqlCleanupBatchSize := 1000
	if v, ok := ctx.Value(cleanupBatchSizeKey).(int); ok {
		mysqlCleanupBatchSize = v
	}

	var err error
	startTime := time.Now()
	defer func() {
		appctx.Logger(ctx).WithError(err).Info("AlertData request",
			kvp.Float64("gh.operation.duration", float64(time.Since(startTime))),
			repositoryID.AsKVP(),
		)
	}()

	for _, table := range AlertTablesToDelete() {
		err := s.deleteTableByRepoID(ctx, repositoryID, table, mysqlCleanupBatchSize)
		if err != nil {
			return err
		}
	}
	return nil
}

// deleteTableByRepoID deletes DB entities for the specified table which relate to the repo with the given ID.
func (s *RepositoryCleanupService) deleteTableByRepoID(ctx context.Context, repositoryID ts.RepositoryEID, table string, mysqlCleanupBatchSize int) error {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()
	db := otelgorm.SetSpanToGorm(ctx, s.db)

	var err error
	startTime := time.Now()
	defer func() {
		appctx.Stats(ctx).DistributionMs("repo_cleanup.delete_table", stats.Tags{"table": table}, time.Since(startTime))
		appctx.Logger(ctx).WithError(err).Info("deleteTableByRepoID request",
			kvp.Float64("gh.operation.duration", float64(time.Since(startTime))),
			kvp.String("gh.turboscan.table", table),
			repositoryID.AsKVP(),
		)
	}()

	idsQuery := db.Table(table).
		Where("repository_id = ?", repositoryID).
		Select("id")

	// Count total number of objects to delete - this is just for debugging purposes.
	var total int64
	err = idsQuery.Count(&total).Error
	if err != nil {
		return errors.Wrap(err, "Failed to count IDs to delete.")
	}

	if total == 0 {
		return nil
	}

	appctx.Logger(ctx).Info("Total count of entries to delete...",
		repositoryID.AsKVP(),
		kvp.String("gh.turboscan.table", table),
		kvp.Int64("gh.turboscan.total", total))

	for !s.DeadlineExceeded() {
		// Make sure the DB is not overloaded
		err = s.WaitOnMySQLWrite(ctx)
		if err != nil {
			return err
		}

		// Fetch a batch of IDs to delete
		idsQuery = idsQuery.Limit(mysqlCleanupBatchSize)

		var ids []uint64
		err = idsQuery.Pluck("id", &ids).Error
		if err != nil {
			return errors.Wrap(err, "Failed to fetch IDs to delete.")
		}

		if len(ids) == 0 {
			return nil
		}

		// Delete IDs
		deleteQuery := db.Table(table).Where(
			"repository_id = ? AND id IN (?)",
			repositoryID, ids,
		).Delete("")
		if err := deleteQuery.Error; err != nil {
			return errors.Wrap(err, "Failed to delete from table.")
		}
		appctx.Logger(ctx).Info("Deleted entities.",
			repositoryID.AsKVP(),
			kvp.String("gh.turboscan.table", table),
			kvp.Int64("gh.turboscan.deleted", deleteQuery.RowsAffected))
		appctx.Stats(ctx).Counter("repo_cleanup.deleted", stats.Tags{"source": "mysql", "table": table}, deleteQuery.RowsAffected)

		// Update the repository progress
		if s.dr != nil {
			err = s.dr.DeleteProgressMysql(ctx, repositoryID, uint64(deleteQuery.RowsAffected))
			if err != nil {
				return err
			}
		}
	}

	return nil
}
