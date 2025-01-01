package data

import (
	"context"
	"time"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-stats"
	"github.com/github/turboghas/internal/fromctx"
	v1 "github.com/github/turboghas/internal/monolith_twirp/turboghas/v1"
	"github.com/pkg/errors"
	"github.com/simon-engledew/sqlh"
	"golang.org/x/exp/slices"
)

type UpsertEntityArgs struct {
	EntityType v1.EntityType
	EntityID   uint64
	UserIDs    []uint64
}

func (d *Data) HasContributorsCache(ctx context.Context, ownerID UserID, at *time.Time) (bool, error) {
	// ensure both dates are compared in UTC, regardless of server timezone
	var unix int64
	if at != nil {
		unix = at.Unix()
	}
	return pluckBool(d.db.Primary.QueryRowContext(ctx, `SELECT 1
      FROM tg_purchasers
INNER JOIN tg_entities
        ON tg_entities.entity_type = tg_purchasers.entity_type
       AND tg_entities.entity_id = tg_purchasers.entity_id
     WHERE tg_purchasers.owner_id = ?
       AND tg_entities.user_ids != CAST('null' AS JSON)
       AND UNIX_TIMESTAMP(tg_entities.updated_at) >= ?`, ownerID, unix))
}

func (d *Data) UpsertEntity(ctx context.Context, args UpsertEntityArgs) error {
	slices.Sort(args.UserIDs)

	// store this as [] in the database rather than null
	if args.UserIDs == nil {
		args.UserIDs = []uint64{}
	}

	userIDs := sqlh.Json(args.UserIDs)

	err := Upserter(ctx, d.db, stats.Tags{"table": "tg_entities"}).
		Touch(`UPDATE tg_entities SET updated_at = NOW()
WHERE user_ids = CAST(? AS JSON)
  AND entity_type = ?
  AND entity_id = ?`,
			userIDs,
			args.EntityType,
			args.EntityID,
		).
		Update(`UPDATE tg_entities
SET updated_at = NOW(), user_ids = ?
WHERE entity_type = ?
AND entity_id = ?`,
			userIDs,
			args.EntityType,
			args.EntityID,
		).
		Insert(`INSERT INTO tg_entities (created_at, updated_at, user_ids, entity_type, entity_id)
VALUES (NOW(), NOW(), ?, ?, ?)
ON DUPLICATE KEY UPDATE updated_at = NOW(), user_ids = VALUES(user_ids)`,
			userIDs,
			args.EntityType,
			args.EntityID,
		)

	return errors.Wrap(err, "upsert entity failed")
}

func (d *Data) DeleteEntity(ctx context.Context, entityID uint64, entityType v1.EntityType) error {
	res, err := d.db.Primary.ExecContext(ctx, "DELETE FROM tg_entities WHERE entity_id = ? AND entity_type = ? LIMIT 1", entityID, entityType)
	if err == nil && rowsAffected(res) > 0 {
		fromctx.Statter.Value(ctx).Counter("data.delete", stats.Tags{"table": "tg_entities"}, rowsAffected(res))
		fromctx.Logger.Value(ctx).Info("deleted entity",
			kvp.Uint64("gh.turboghas.entity_id", entityID),
			kvp.String("gh.turboghas.entity_type", entityType.String()),
		)
	}
	return errors.Wrap(err, "failed to delete entity")
}
