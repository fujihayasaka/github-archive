package api_test

import (
	"testing"

	"github.com/github/turboghas/internal/api"
	"github.com/github/turboghas/internal/dbtest"
	v1 "github.com/github/turboghas/internal/monolith_twirp/turboghas/v1"
	"github.com/github/turboghas/proto"
	"github.com/stretchr/testify/require"
)

func TestGetActiveCommitters_noFeatures(t *testing.T) {
	db := dbtest.Seed(t)

	handler := api.New(dbtest.Dual(db))

	replay(t, "get-active-committers-no-features", handler)

	ctx := t.Context()
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

func TestGetActiveCommitters_allFeatures(t *testing.T) {
	db := dbtest.Seed(t)

	handler := api.New(dbtest.Dual(db))

	replay(t, "get-active-committers-all-features", handler)

	ctx := t.Context()
	advancedSecurityAPI := api.NewAdvancedSecurityAPI(db)

	summaryResp, err := advancedSecurityAPI.GetSummary(ctx, &proto.GetSummaryRequest{
		EntityType: v1.EntityType_ENTITY_TYPE_BUSINESS,
		EntityId:   1,
		Features:   []v1.Feature{v1.Feature_FEATURE_ALL},
	})
	require.NoError(t, err)
	require.NotZero(t, summaryResp.ActiveCommitters)

	activeCommittersResp, err := advancedSecurityAPI.GetActiveCommitters(ctx, &proto.GetActiveCommittersRequest{
		EntityType: v1.EntityType_ENTITY_TYPE_BUSINESS,
		EntityId:   1,
		Features:   []v1.Feature{v1.Feature_FEATURE_ALL},
	})
	require.NoError(t, err)
	require.Len(t, activeCommittersResp.Users, int(summaryResp.ActiveCommitters))
}

func TestGetActiveCommitters_codeScanning(t *testing.T) {
	db := dbtest.Seed(t)
	handler := api.New(dbtest.Dual(db))
	replay(t, "get-active-committers-code-scanning", handler)

	ctx := t.Context()
	advancedSecurityAPI := api.NewAdvancedSecurityAPI(db)

	summaryResp, err := advancedSecurityAPI.GetSummary(ctx, &proto.GetSummaryRequest{
		EntityType: v1.EntityType_ENTITY_TYPE_BUSINESS,
		EntityId:   1,
		Features:   []v1.Feature{v1.Feature_FEATURE_CODE_SCANNING},
	})
	require.NoError(t, err)
	require.NotZero(t, summaryResp.ActiveCommitters)

	activeCommittersResp, err := advancedSecurityAPI.GetActiveCommitters(ctx, &proto.GetActiveCommittersRequest{
		EntityType: v1.EntityType_ENTITY_TYPE_BUSINESS,
		EntityId:   1,
		Features:   []v1.Feature{v1.Feature_FEATURE_CODE_SCANNING},
	})
	require.NoError(t, err)
	require.Len(t, activeCommittersResp.Users, int(summaryResp.ActiveCommitters))
}

func TestGetActiveCommitters_secretScanning(t *testing.T) {
	db := dbtest.Seed(t)
	handler := api.New(dbtest.Dual(db))
	replay(t, "get-active-committers-secret-scanning", handler)

	ctx := t.Context()
	advancedSecurityAPI := api.NewAdvancedSecurityAPI(db)

	summaryResp, err := advancedSecurityAPI.GetSummary(ctx, &proto.GetSummaryRequest{
		EntityType: v1.EntityType_ENTITY_TYPE_BUSINESS,
		EntityId:   1,
		Features:   []v1.Feature{v1.Feature_FEATURE_SECRET_SCANNING},
	})
	require.NoError(t, err)
	require.NotZero(t, summaryResp.ActiveCommitters)

	activeCommittersResp, err := advancedSecurityAPI.GetActiveCommitters(ctx, &proto.GetActiveCommittersRequest{
		EntityType: v1.EntityType_ENTITY_TYPE_BUSINESS,
		EntityId:   1,
		Features:   []v1.Feature{v1.Feature_FEATURE_SECRET_SCANNING},
	})
	require.NoError(t, err)
	require.Len(t, activeCommittersResp.Users, int(summaryResp.ActiveCommitters))
}
