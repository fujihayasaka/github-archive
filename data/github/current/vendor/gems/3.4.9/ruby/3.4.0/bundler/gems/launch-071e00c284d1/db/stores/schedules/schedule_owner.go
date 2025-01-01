package schedules

import (
	"context"
	"fmt"

	"github.com/pkg/errors"

	"github.com/github/launch/observability/tracing"
	"github.com/github/launch/types"
	"github.com/github/launch/utils/asql"
)

func (r *dbStore) UpdateOwnerID(ctx context.Context, repoNodeID types.GlobalID, ownerID int64) error {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	repositoryNextID, repositoryNodeNextColumn, err := r.gidMigrator.GetNextGlobalIDAndColumnForQuery(ctx, repoNodeID.String(), repositoryNodeColumnName)
	if err != nil {
		return errors.Wrap(err, "Failed to get next repository id and column for dbStore when updating Owner ID")
	}

	query := fmt.Sprintf(`UPDATE workflow_schedules
	SET owner_id = ?
	WHERE %s = ?
		AND environment = ?
	ORDER BY next_run_at ASC`, repositoryNodeNextColumn)

	_, err = r.DB.ExecContextWith(
		ctx,
		query,
		asql.WithName("UpdateOwnerID"), asql.Params(ownerID, repositoryNextID, r.Cfg.Environment)...,
	)

	return err
}
