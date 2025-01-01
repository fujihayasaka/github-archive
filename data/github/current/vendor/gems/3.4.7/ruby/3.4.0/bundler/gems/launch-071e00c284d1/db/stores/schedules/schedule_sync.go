package schedules

import (
	"context"
	"crypto/sha256"
	"database/sql"
	"encoding/base64"
	"errors"
	"fmt"
	"math/rand"
	"strings"

	"github.com/github/go-kvp"

	errs "github.com/pkg/errors"

	"github.com/github/launch/mysqldb"
	"github.com/github/launch/observability/statter"
	"github.com/github/launch/observability/tracing"
	"github.com/github/launch/services/deploy/scheduled/model"
	"github.com/github/launch/types"
	"github.com/github/launch/utils/asql"
)

const (
	scheduleHashColumnName   = "schedule_hash"
	repositoryNodeColumnName = "repository_node_id"
)

// NewScheduleHash returns URL-safe base64 encoding of sha256 of logical identifiers of a schedule
func NewScheduleHash(repoGlobalID types.GlobalID, workflowIdentifer string, workflowFilePath string, schedule string) string {
	hasher := sha256.New()
	_, _ = fmt.Fprint(hasher, repoGlobalID, workflowFilePath, workflowIdentifer, schedule)
	return base64.URLEncoding.EncodeToString(hasher.Sum(nil))
}

func (r *dbStore) PersistUpdate(ctx context.Context, update model.ScheduleSync) (err error) {
	// The approach here is to generate all the logical identifiers present for the new state, delete
	// all the rows not present in that state, then upsert the rest. Unchanged rows will have their
	// commit SHA updated to reflect the latest change.
	ctx, span := tracing.Start(ctx)
	defer span.End()

	r.obs.Logger.Log(ctx, "syncing schedules", kvp.Int("count", len(update.FlowIdentifiersToSchedule)))

	workflowScheduleHashesPresent := make([]any, 0, len(update.FlowIdentifiersToSchedule))

	repositoryNextID, err := r.gidMigrator.GetNextGlobalID(ctx, update.RepoNodeID.String())
	if err != nil {
		return tracing.RecordError(span, errs.Wrap(err, "Failed to get next repository id for dbStore"))
	}
	repoNextIDForQuery, repositoryNodeNextColumn, err := r.gidMigrator.GetNextGlobalIDAndColumnForQuery(ctx, update.RepoNodeID.String(), repositoryNodeColumnName)
	if err != nil {
		return tracing.RecordError(span, errs.Wrap(err, "Failed to get next repository id and column for dbStore"))
	}

	actorNextID, err := r.gidMigrator.GetNextGlobalID(ctx, update.ActorID.String())
	if err != nil {
		return tracing.RecordError(span, errs.Wrap(err, "Failed to get next actor id for dbStore"))
	}

	_, scheduleHashNextColumn, err := r.gidMigrator.GetNextGlobalIDAndColumnForQuery(ctx, update.RepoNodeID.String(), scheduleHashColumnName)
	if err != nil {
		return tracing.RecordError(span, errs.Wrap(err, "Failed to get schedule hash column for dbStore"))
	}

	scheduleHashFor := func(flowSelector types.WorkflowSelector, scheduleExpression string) string {
		return NewScheduleHash(update.RepoNodeID, flowSelector.Identifier, flowSelector.WorkflowPath, scheduleExpression)
	}

	scheduleNextHashFor := func(flowSelector types.WorkflowSelector, scheduleExpression string) string {
		return NewScheduleHash(repositoryNextID, flowSelector.Identifier, flowSelector.WorkflowPath, scheduleExpression)
	}

	for flowID, scheduleExpression := range update.FlowIdentifiersToSchedule {
		// Comparing schedule hash column name to avoid multiple FF checks which could result in mismatches
		if scheduleHashNextColumn == scheduleHashColumnName {
			workflowScheduleHashesPresent = append(workflowScheduleHashesPresent,
				scheduleHashFor(flowID, scheduleExpression))
		} else {
			workflowScheduleHashesPresent = append(workflowScheduleHashesPresent,
				scheduleNextHashFor(flowID, scheduleExpression))
		}
	}

	if len(workflowScheduleHashesPresent) == 0 {
		err := r.RemoveSchedules(ctx, update.RepoNodeID)
		if err != nil {
			return errs.Wrap(err, "failed to delete schedules")
		}

		return nil
	}

	if update.ActorID == "" || update.ActorLogin == "" {
		return errors.New("missing actor id or actor login for schedule update")
	}

	// Log if legacy global ID is being replaced
	if update.RepoNodeID != repositoryNextID {
		r.logGlobalIDReplacement(ctx, "repository_node_id", update.RepoNodeID.String(), repositoryNextID.String())
		r.logGlobalIDReplacement(ctx,
			"schedule_hash",
			fmt.Sprintf("base64(\"%s<schedule format>\")", update.RepoNodeID.String()),
			fmt.Sprintf("base64(\"%s<schedule format>\")", repositoryNextID.String()))
	}
	if update.ActorID != actorNextID {
		r.logGlobalIDReplacement(ctx, "actor_node_id", update.ActorID.String(), actorNextID.String())
	}

	update.RepoNodeID = repositoryNextID
	update.ActorID = actorNextID

	err = mysqldb.WithTransaction(ctx, r.DB.Conn(), r.obs.Statter, "SyncSchedules", func(tx *sql.Tx) error {
		invalidFrag := ""
		if len(update.InvalidFiles) > 0 {
			invalidFrag = fmt.Sprintf("OR workflow_file_path IN (%s)", mysqldb.Placeholders(len(update.InvalidFiles)))
		}

		deleteSQL := fmt.Sprintf(`
			DELETE FROM workflow_schedules
			WHERE (
				%s NOT IN (%s)
				%s
			)
				AND %s = ?
				AND environment = ?
			ORDER BY next_run_at ASC
		`, scheduleHashNextColumn, mysqldb.Placeholders(len(workflowScheduleHashesPresent)), invalidFrag, repositoryNodeNextColumn)
		args := append(
			append(workflowScheduleHashesPresent, stringsToEmptyInterfaces(update.InvalidFiles)...),
			string(repoNextIDForQuery),
			r.Cfg.Environment,
		)
		_, err = r.DB.ExecTx(ctx, tx, deleteSQL, asql.WithName("DeleteSchedules"), args...)
		if err != nil {
			return errs.Wrap(err, "failed to delete schedules")
		}

		// This number should match the number of entries in params below
		paramsPerRow := 17

		params := make([]any, 0, len(workflowScheduleHashesPresent)*paramsPerRow)
		insertRows := make([]string, 0, len(workflowScheduleHashesPresent))

		for flowIdentifier, scheduleExpression := range update.FlowIdentifiersToSchedule {
			offset := rand.Float64()
			scheduleHash := scheduleHashFor(flowIdentifier, scheduleExpression)
			scheduleHashNext := scheduleNextHashFor(flowIdentifier, scheduleExpression)

			schedule, err := r.ScheduleParser.ParseExpression(scheduleExpression)
			if err != nil {
				return errs.Wrap(err, "failed to parse schedule expression")
			}

			params = append(params, []any{
				update.Tier,
				r.clock.Now().UTC(),
				scheduleHash,
				wrapNullString(scheduleHashNext),
				update.RepoNodeID,
				wrapNullString(repositoryNextID.String()),
				wrapNullInt64(update.OwnerID),
				flowIdentifier.Identifier,
				flowIdentifier.WorkflowPath,
				r.Cfg.Environment,
				scheduleExpression,
				offset,
				update.CommitSHA,
				string(update.ActorID),
				wrapNullString(actorNextID.String()),
				update.ActorLogin,
				schedule.Next(r.clock.Now().UTC()),
			}...)

			// Sprintf'ing next_run_at is required as we can't use ? for a `INTERVAL` expression. It's safe
			// as it's a numeric value we control
			scatterFmt := fmt.Sprintf("DATE_ADD(?, INTERVAL %f SECOND)",
				scaleScatterOffsetByTier(update.Tier, offset*r.Cfg.ScatterOffsetDuration.Seconds()))

			insertRows = append(
				insertRows,
				fmt.Sprintf("(%s, %s)",
					mysqldb.Placeholders(paramsPerRow-1),
					scatterFmt,
				),
			)
		}

		insertSQL := fmt.Sprintf(`
			INSERT INTO workflow_schedules
				(
					tier,
					created_at,
					schedule_hash,
					schedule_next_hash,
					repository_node_id,
					repository_next_id,
					owner_id,
					workflow_identifier,
					workflow_file_path,
					environment,
					schedule,
					scatter_offset,
					commit_sha,
					actor_node_id,
					actor_next_id,
					actor_login,
					next_run_at
				)
			VALUES %s
			ON DUPLICATE KEY UPDATE id=id, commit_sha=values(commit_sha), owner_id=values(owner_id)
			`,
			strings.Join(insertRows, ","),
		)

		if _, err = r.DB.ExecTx(ctx, tx, insertSQL, asql.WithName("InsertOrUpdateSchedules"), params...); err != nil {
			return errs.Wrap(err, "failed to insert or update schedules")
		}

		return nil
	})

	if err != nil {
		return errs.Wrap(err, "failed to complete transaction")
	}

	return nil
}

func stringsToEmptyInterfaces(ss []string) []any {
	eis := make([]any, 0, len(ss))
	for _, s := range ss {
		eis = append(eis, s)
	}
	return eis
}

func (r *dbStore) RemoveSchedules(ctx context.Context, repoGID types.GlobalID) error {
	name := "RemoveSchedules"

	repositoryNextID, repositoryNodeNextColumn, err := r.gidMigrator.GetNextGlobalIDAndColumnForQuery(ctx, repoGID.String(), repositoryNodeColumnName)
	if err != nil {
		return errs.Wrap(err, "Failed to get next repository id and column for dbStore")
	}

	query := fmt.Sprintf(`DELETE FROM workflow_schedules
	WHERE %s = ?
		AND environment = ?
	ORDER BY next_run_at ASC`, repositoryNodeNextColumn)

	_, err = mysqldb.WithDeadlockRetry(ctx, name, r.obs.Statter, func() (sql.Result, error) {
		return r.DB.ExecContextWith(ctx, query, asql.WithName(name), repositoryNextID, r.Cfg.Environment)
	})
	if err != nil {
		return errs.Wrap(err, "failed to run delete rows")
	}
	return nil
}

func wrapNullString(s string) sql.NullString {
	if s == "" {
		return sql.NullString{}
	}

	return sql.NullString{
		String: s,
		Valid:  true,
	}
}

func wrapNullInt64(i int64) sql.NullInt64 {
	if i <= 0 {
		return sql.NullInt64{}
	}

	return sql.NullInt64{
		Int64: i,
		Valid: true,
	}
}

func (r *dbStore) logGlobalIDReplacement(ctx context.Context, field string, legacyGID, nextGID string) {
	r.obs.Counter(ctx, "global_ids.replace_wfs_legacy_id", statter.Tags{"operation": "PersistUpdate", "column": field}, 1)
	r.obs.Logger.Debug(ctx, "Replacing legacy global id with next value for workflow_schedules column",
		kvp.String("column", field),
		kvp.String("legacy_global_id", legacyGID),
		kvp.String("next_global_id", nextGID))
}
