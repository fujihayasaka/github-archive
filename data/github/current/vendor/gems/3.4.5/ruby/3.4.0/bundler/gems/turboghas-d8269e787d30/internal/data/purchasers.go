package data

import (
	"context"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-stats"
	"github.com/github/turboghas/internal/fromctx"
	v1 "github.com/github/turboghas/internal/monolith_twirp/turboghas/v1"
	"github.com/pkg/errors"
)

type UpsertPurchaserArgs struct {
	OwnerID    UserID
	EntityType v1.EntityType
	EntityID   uint64
}

func (d *Data) UpsertPurchaser(ctx context.Context, args UpsertPurchaserArgs) error {
	err := Upserter(ctx, d.db, stats.Tags{"table": "tg_purchasers"}).
		Select(`SELECT 1
 FROM tg_purchasers
WHERE entity_type = ?
  AND entity_id = ?
  AND owner_id = ?`,
			args.EntityType,
			args.EntityID,
			args.OwnerID,
		).
		Update(
			`UPDATE tg_purchasers
SET updated_at = NOW(), entity_type = ?, entity_id = ?
WHERE owner_id = ?`,
			args.EntityType,
			args.EntityID,
			args.OwnerID,
		).
		Insert(`INSERT INTO tg_purchasers (created_at, updated_at, entity_type, entity_id, owner_id)
VALUES (NOW(), NOW(), ?, ?, ?)
ON DUPLICATE KEY
UPDATE
    updated_at = NOW(),
    entity_type = VALUES(entity_type),
    entity_id = VALUES(entity_id)`,
			args.EntityType,
			args.EntityID,
			args.OwnerID,
		)

	return errors.Wrap(err, "upsert purchaser failed")
}

func (d *Data) DeletePurchaser(ctx context.Context, ownerID UserID) error {
	res, err := d.db.Primary.ExecContext(ctx, "DELETE FROM tg_purchasers WHERE owner_id = ? LIMIT 1", ownerID)
	if err == nil && rowsAffected(res) > 0 {
		fromctx.Statter.Value(ctx).Counter("data.delete", stats.Tags{"table": "tg_purchasers"}, rowsAffected(res))
		fromctx.Logger.Value(ctx).Info("deleted purchaser", kvp.Uint64("gh.turboghas.owner_id", uint64(ownerID)))
	}
	return errors.Wrap(err, "failed to delete purchaser")
}
