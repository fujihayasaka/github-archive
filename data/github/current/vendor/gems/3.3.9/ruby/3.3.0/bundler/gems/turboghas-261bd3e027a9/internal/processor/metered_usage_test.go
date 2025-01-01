package processor_test

import (
	"context"
	"testing"

	billingplatformv1 "github.com/github/hydro-schemas-go/hydro/schemas/billingplatform/v1"
	"github.com/github/hydro-schemas-go/hydro/schemas/billingplatform/v1/entities"
	"github.com/github/turboghas/internal/dbtest"
	"github.com/github/turboghas/internal/processor"
	"github.com/stretchr/testify/require"
)

func TestMeteredUsage(t *testing.T) {
	db := dbtest.Seed(t)
	d := dbtest.Data(db)
	ctx := context.Background()

	require.NoError(t, processor.New(d, &mockApi{}, &mockPublisher{}, nil, &mockDeps{}).ProcessMessage(ctx, &billingplatformv1.Usage{
		Quantity: 1,
		Sku:      "ghas_seats",
		Entity: &entities.EntityDetail{
			CustomerId: 1,
			ActorId:    1,
		},
	}))

	require.True(t, dbtest.RequireScan[bool](t, db.QueryRow("SELECT EXISTS(SELECT 1 FROM tg_meter_emissions WHERE customer_id = 1)")))

	require.NoError(t, processor.New(d, &mockApi{}, &mockPublisher{}, nil, &mockDeps{}).ProcessMessage(ctx, &billingplatformv1.Usage{
		Quantity: -1,
		Sku:      "ghas_seats",
		Entity: &entities.EntityDetail{
			CustomerId: 1,
			ActorId:    1,
		},
	}))

	require.False(t, dbtest.RequireScan[bool](t, db.QueryRow("SELECT EXISTS(SELECT 1 FROM tg_meter_emissions WHERE customer_id = 1)")))
}
