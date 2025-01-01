package data_test

import (
	"testing"
	"time"

	"github.com/SamuelTissot/sqltime"

	"github.com/github/turboghas/internal/data"
	"github.com/github/turboghas/internal/dbtest"
	v1 "github.com/github/turboghas/internal/monolith_twirp/turboghas/v1"
	"github.com/stretchr/testify/require"
)

func TestMeterEmissions(t *testing.T) {
	ctx := t.Context()
	db := dbtest.RequireConnection(t)
	d := dbtest.Data(db)

	now := sqltime.Time{Time: time.Now()}

	require.NoError(t, d.UpsertMeterEmission(ctx, data.UpsertMeterEmissionArgs{
		MeterEmissionArgs: data.MeterEmissionArgs{
			CustomerID: uint64(1),
			ActorID:    uint64(1),
			SKU:        v1.SKU_SKU_GHAS_SEATS,
		},
		UsageAt: now.Time,
	}))

	require.Equal(t, 1, dbtest.RequireScan[int](t, db.QueryRow("SELECT COUNT(1) FROM tg_meter_emissions")))

	// simulate a record in the old format
	_, err := db.Exec(`UPDATE tg_meter_emissions SET usage_at = NULL`)
	require.NoError(t, err)

	require.NoError(t, d.UpsertMeterEmission(ctx, data.UpsertMeterEmissionArgs{
		MeterEmissionArgs: data.MeterEmissionArgs{
			CustomerID: uint64(1),
			ActorID:    uint64(1),
			SKU:        v1.SKU_SKU_GHAS_SEATS,
		},
		UsageAt: now.Time,
	}))

	// check we overwrote the usage_at column even though it was NULL
	require.Equal(t, 0, dbtest.RequireScan[int](t, db.QueryRow("SELECT COUNT(1) FROM tg_meter_emissions WHERE usage_at IS NULL")))
	require.Equal(t, 1, dbtest.RequireScan[int](t, db.QueryRow("SELECT COUNT(1) FROM tg_meter_emissions WHERE usage_at = ?", now)))

	then := sqltime.Time{Time: now.Add(-24 * time.Hour)}

	require.NoError(t, d.UpsertMeterEmission(ctx, data.UpsertMeterEmissionArgs{
		MeterEmissionArgs: data.MeterEmissionArgs{
			CustomerID: uint64(1),
			ActorID:    uint64(1),
			SKU:        v1.SKU_SKU_GHAS_SEATS,
		},
		UsageAt: then.Time,
	}))

	// check we used the greater of the two timestamps
	require.Equal(t, 0, dbtest.RequireScan[int](t, db.QueryRow("SELECT COUNT(1) FROM tg_meter_emissions WHERE usage_at = ?", then)))
	require.Equal(t, 1, dbtest.RequireScan[int](t, db.QueryRow("SELECT COUNT(1) FROM tg_meter_emissions WHERE usage_at = ?", now)))
}
