package data

import (
	"context"
	"time"

	"github.com/SamuelTissot/sqltime"

	v1 "github.com/github/turboghas/internal/monolith_twirp/turboghas/v1"

	"github.com/pkg/errors"
)

type MeterEmissionArgs struct {
	CustomerID uint64
	ActorID    uint64
	SKU        v1.SKU
}

type UpsertMeterEmissionArgs struct {
	MeterEmissionArgs
	UsageAt time.Time
}

func (d *Data) UpsertMeterEmission(ctx context.Context, args UpsertMeterEmissionArgs) error {
	if args.SKU == v1.SKU_SKU_INVALID {
		return errors.New("invalid SKU")
	}

	// GREATEST always returns NULL if an argument is NULL
	// COALESCE(usage_at, VALUES(usage_at)) stops the value from being NULL
	// We could transition all the existing NULL usage_at values and set the column to NOT NULL and this would no
	// longer be necessary
	_, err := d.db.Primary.ExecContext(ctx, `INSERT INTO tg_meter_emissions (created_at, updated_at, customer_id, actor_id, sku, usage_at)
VALUES (NOW(), NOW(), ?, ?, ?, ?)
ON DUPLICATE KEY
UPDATE updated_at = NOW(), usage_at = GREATEST(COALESCE(usage_at, VALUES(usage_at)), VALUES(usage_at))`,
		args.CustomerID,
		args.ActorID,
		args.SKU,
		sqltime.Time{Time: args.UsageAt},
	)

	return errors.Wrap(err, "failed to upsert meter emissions")
}

func (d *Data) DeleteMeterEmission(ctx context.Context, args MeterEmissionArgs) error {
	if args.SKU == v1.SKU_SKU_INVALID {
		return errors.New("invalid SKU")
	}

	_, err := d.db.Primary.ExecContext(ctx, `DELETE FROM tg_meter_emissions WHERE customer_id = ? AND actor_id = ? AND sku = ? LIMIT 1`,
		args.CustomerID,
		args.ActorID,
		args.SKU,
	)

	return errors.Wrap(err, "failed to delete meter emissions")
}
