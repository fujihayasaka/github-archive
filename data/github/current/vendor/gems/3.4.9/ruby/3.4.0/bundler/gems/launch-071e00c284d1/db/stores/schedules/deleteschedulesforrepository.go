package schedules

import (
	"context"
	"fmt"

	"github.com/pkg/errors"

	launchconfig "github.com/github/launch/pkg/launchconfig"
	"github.com/github/launch/types"
	"github.com/github/launch/utils/asql"
)

// DeleteSchedulesForRepository deletes all scheduled workflows for the given repository in the given environment
func (r *dbStore) DeleteSchedulesForRepository(ctx context.Context, env launchconfig.AppEnv, id types.GlobalID) (int64, error) {
	repositoryNextID, repositoryNodeNextColumn, err := r.gidMigrator.GetNextGlobalIDAndColumnForQuery(ctx, id.String(), repositoryNodeColumnName)
	if err != nil {
		return 0, errors.Wrap(err, "Failed to get next repository id and column for dbStore")
	}

	stmt := fmt.Sprintf(`DELETE FROM workflow_schedules WHERE %s = ? AND environment = ?`, repositoryNodeNextColumn)
	result, err := r.DB.ExecContextWith(ctx, stmt, asql.WithName("DeleteSchedulesForRepository"), repositoryNextID, env)
	if err != nil {
		return 0, err
	}
	return result.RowsAffected()
}
