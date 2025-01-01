package api_test

import (
	"context"
	"testing"

	"github.com/github/turboghas/internal/api"
	"github.com/github/turboghas/internal/dbtest"
	v1 "github.com/github/turboghas/internal/monolith_twirp/turboghas/v1"
	"github.com/github/turboghas/proto"
	"github.com/stretchr/testify/require"
)

func TestGetActiveCommitters(t *testing.T) {
	db := dbtest.Seed(t)

	handler := api.New(dbtest.Dual(db))

	replay(t, "get-active-committers", handler)

	ctx := context.Background()
	advancedSecurityAPI := api.NewAdvancedSecurityAPI(db)

	summaryResp, err := advancedSecurityAPI.GetSummary(ctx, &proto.GetSummaryRequest{
		EntityType: v1.EntityType_ENTITY_TYPE_BUSINESS,
		EntityId:   1,
	})
	require.NoError(t, err)
	require.NotZero(t, summaryResp.ActiveCommitters)

	activeCommittersResp, err := advancedSecurityAPI.GetActiveCommitters(ctx, &proto.GetActiveCommittersRequest{
		EntityType: v1.EntityType_ENTITY_TYPE_BUSINESS,
		EntityId:   1,
	})
	require.NoError(t, err)
	require.Len(t, activeCommittersResp.Users, int(summaryResp.ActiveCommitters))
}
