package api_test

import (
	"context"
	"testing"

	"github.com/github/turboghas/internal/api"
	"github.com/github/turboghas/internal/data"
	"github.com/github/turboghas/internal/dbtest"
	"github.com/stretchr/testify/require"
)

func TestGetSummary(t *testing.T) {
	db := dbtest.Seed(t)

	handler := api.New(dbtest.Dual(db))

	ctx := context.Background()

	// simulate some GHES meter usage
	require.NoError(t, dbtest.Data(db).UpsertMeterEmission(ctx, data.UpsertMeterEmissionArgs{CustomerID: 1, ActorID: 10}))

	replay(t, "get-summary", handler)
}
