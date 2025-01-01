package data

import (
	"context"

	"github.com/pkg/errors"
)

type UpsertMeterEmissionArgs struct {
	CustomerID uint64
	ActorID    uint64
}

func (d *Data) UpsertMeterEmission(ctx context.Context, args UpsertMeterEmissionArgs) error {
	_, err := d.db.Primary.ExecContext(ctx, `INSERT INTO tg_meter_emissions (created_at, updated_at, customer_id, actor_id)
VALUES (NOW(), NOW(), ?, ?)
ON DUPLICATE KEY
UPDATE updated_at = NOW()`,
		args.CustomerID,
		args.ActorID,
	)

	return errors.Wrap(err, "failed to upsert meter emissions")
}

func (d *Data) DeleteMeterEmission(ctx context.Context, args UpsertMeterEmissionArgs) error {
	_, err := d.db.Primary.ExecContext(ctx, `DELETE FROM tg_meter_emissions WHERE customer_id = ? AND actor_id = ? LIMIT 1`,
		args.CustomerID,
		args.ActorID,
	)

	return errors.Wrap(err, "failed to delete meter emissions")
}
