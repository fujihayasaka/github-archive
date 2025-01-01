package schedules

import (
	"context"
	"database/sql"
	"fmt"

	"github.com/pkg/errors"

	"github.com/github/launch/mysqldb"
	launchconfig "github.com/github/launch/pkg/launchconfig"
	"github.com/github/launch/types"
	"github.com/github/launch/utils/asql"
)

// DeleteScheduleForWorkflow deletes a single schedule for a workflow for the given repository in the given environment
func (r *dbStore) DeleteScheduleForWorkflow(ctx context.Context, env launchconfig.AppEnv, repoID types.GlobalID, workflowFilePath string) (int64, error) {
	repositoryNextID, repositoryNodeNextColumn, err := r.gidMigrator.GetNextGlobalIDAndColumnForQuery(ctx, repoID.String(), repositoryNodeColumnName)
	if err != nil {
		return 0, errors.Wrap(err, "Failed to get next repository id and column for dbStore")
	}
	stmt := fmt.Sprintf(`DELETE FROM workflow_schedules WHERE %s = ? AND environment = ? AND workflow_file_path = ?`, repositoryNodeNextColumn)

	name := "DeleteScheduleForWorkflow"
	result, err := mysqldb.WithDeadlockRetry(ctx, name, r.obs.Statter, func() (sql.Result, error) {
		return r.DB.ExecContextWith(ctx, stmt, asql.WithName(name), repositoryNextID, env, workflowFilePath)
	})
	if err != nil {
		return 0, err
	}
	return result.RowsAffected()
}
