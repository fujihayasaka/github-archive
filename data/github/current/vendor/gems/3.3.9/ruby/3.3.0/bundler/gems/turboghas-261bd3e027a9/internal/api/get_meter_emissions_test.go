package api_test

import (
	"context"
	"testing"

	"github.com/github/turboghas/internal/api"
	"github.com/github/turboghas/internal/data"
	"github.com/github/turboghas/internal/dbtest"
	v1 "github.com/github/turboghas/internal/monolith_twirp/turboghas/v1"
	"github.com/github/turboghas/proto"
	"github.com/stretchr/testify/require"
)

func TestGetMeterEmissions(t *testing.T) {
	db := dbtest.Seed(t)

	handler := api.New(dbtest.Dual(db))

	d := dbtest.Data(db)

	ctx := context.Background()

	require.NoError(t, d.UpsertMeterEmission(ctx, data.UpsertMeterEmissionArgs{CustomerID: 1, ActorID: 1}))
	// there are no tg_contributions in the seed for a user with ID 10, so this will count as the user 10 needing to be removed to make
	// the billing state consistent
	require.NoError(t, d.UpsertMeterEmission(ctx, data.UpsertMeterEmissionArgs{CustomerID: 1, ActorID: 10}))

	replay(t, "get-meter-emissions", handler)

	advancedSecurityAPI := api.NewAdvancedSecurityAPI(db)

	activeCommittersResp, err := advancedSecurityAPI.GetActiveCommitters(ctx, &proto.GetActiveCommittersRequest{
		EntityType: v1.EntityType_ENTITY_TYPE_BUSINESS,
		EntityId:   1,
	})
	require.NoError(t, err)
	require.NotEmpty(t, activeCommittersResp.Users)

	meterEmissionsResp, err := advancedSecurityAPI.GetMeterEmissions(ctx, &proto.GetMeterEmissionsRequest{
		CustomerId: 1,
		EntityType: v1.EntityType_ENTITY_TYPE_BUSINESS,
		EntityId:   1,
	})
	require.NoError(t, err)
	require.NotEmpty(t, meterEmissionsResp.Added)
	require.Subset(t, api.Map(activeCommittersResp.Users, func(u *proto.GetActiveCommittersResponse_User) uint64 {
		return u.Id
	}), meterEmissionsResp.Added)
}

func TestGetMeterEmissionsWithAdditionalUsers(t *testing.T) {
	db := dbtest.Seed(t)

	handler := api.New(dbtest.Dual(db))

	d := dbtest.Data(db)

	ctx := context.Background()

	require.NoError(t, d.UpsertMeterEmission(ctx, data.UpsertMeterEmissionArgs{CustomerID: 1, ActorID: 1}))

	replay(t, "get-meter-emissions-with-additional-users", handler)

	advancedSecurityAPI := api.NewAdvancedSecurityAPI(db)

	activeCommittersResp, err := advancedSecurityAPI.GetActiveCommitters(ctx, &proto.GetActiveCommittersRequest{
		EntityType: v1.EntityType_ENTITY_TYPE_BUSINESS,
		EntityId:   1,
	})
	require.NoError(t, err)
	require.NotEmpty(t, activeCommittersResp.Users)

	// there are no contributions for user 10
	// we are simulating GHES usage that is being provided by dotcom and they should be added
	meterEmissionsResp, err := advancedSecurityAPI.GetMeterEmissions(ctx, &proto.GetMeterEmissionsRequest{
		CustomerId:        1,
		EntityType:        v1.EntityType_ENTITY_TYPE_BUSINESS,
		EntityId:          1,
		AdditionalUserIds: []uint64{10},
	})
	require.NoError(t, err)
	require.NotEmpty(t, meterEmissionsResp.Added)
	require.Contains(t, meterEmissionsResp.Added, uint64(10))
}
