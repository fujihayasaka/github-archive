package suggested_fixes

import (
	"context"
	"strconv"
	"testing"

	"github.com/SamuelTissot/sqltime"
	"github.com/jinzhu/gorm"
	"google.golang.org/protobuf/types/known/timestamppb"

	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/dbtest"
	"github.com/github/turboscan/ts/elasticsearch"
	"github.com/github/turboscan/ts/limits"
	asdb "github.com/github/turboscan/ts/mysql/alert"
	"github.com/github/turboscan/ts/mysql/archiver"
	sfdb "github.com/github/turboscan/ts/mysql/suggestedfixes"
	"github.com/github/turboscan/ts/sarif/store"
	sf "github.com/github/turboscan/ts/suggestedfixes"
	"github.com/github/turboscan/ts/twirp/clients/aqueduct"

	"github.com/stretchr/testify/require"

	"github.com/github/turboscan/ts/proto"
	"github.com/github/turboscan/ts/twirp/clients/spokes"
)

func TestGetSuggestedFixStatesForOrg(t *testing.T) {
	_, ctx, twirpServ, es := setupServiceWithES(t)

	fixedOnDefault := false
	deleted := false
	codeScanningEnabled := true
	now := sqltime.Now()
	err := es.IndexDocuments(ctx, ts.Index_OrgLevel, []*ts.SearchDocument{
		{
			// Without autofix
			OwnerID:             "1",
			RepositoryID:        "1",
			Number:              1,
			AlertID:             7839,
			CanonicalID:         "2789",
			FixedOnDefault:      &fixedOnDefault,
			Deleted:             &deleted,
			CodeScanningEnabled: &codeScanningEnabled,
		},
		{
			// Valid autofix
			OwnerID:               "1",
			RepositoryID:          "1",
			Number:                2,
			AlertID:               7840,
			CanonicalID:           "2783",
			FixedOnDefault:        &fixedOnDefault,
			Deleted:               &deleted,
			CodeScanningEnabled:   &codeScanningEnabled,
			AutofixEligible:       true,
			AutofixState:          ts.SuggestedFixAlertStateValid.DBString(),
			AutofixStateUpdatedAt: &now,
		},
		{
			// Error autofix in other repo
			OwnerID:               "1",
			RepositoryID:          "2",
			Number:                5,
			AlertID:               8993,
			CanonicalID:           "5672",
			FixedOnDefault:        &fixedOnDefault,
			Deleted:               &deleted,
			CodeScanningEnabled:   &codeScanningEnabled,
			AutofixEligible:       true,
			AutofixState:          ts.SuggestedFixAlertStateError.DBString(),
			AutofixStateUpdatedAt: &now,
		},
		{
			// Eligible autofix without state
			OwnerID:             "1",
			RepositoryID:        "2",
			Number:              9,
			AlertID:             9364,
			CanonicalID:         "8947",
			FixedOnDefault:      &fixedOnDefault,
			Deleted:             &deleted,
			CodeScanningEnabled: &codeScanningEnabled,
			AutofixEligible:     true,
		},
		{
			// Valid autofix in other repo not included in the request
			OwnerID:               "1",
			RepositoryID:          "3",
			Number:                1,
			AlertID:               3785,
			CanonicalID:           "6372",
			FixedOnDefault:        &fixedOnDefault,
			Deleted:               &deleted,
			CodeScanningEnabled:   &codeScanningEnabled,
			AutofixEligible:       true,
			AutofixState:          ts.SuggestedFixAlertStateValid.DBString(),
			AutofixStateUpdatedAt: &now,
		},
	})
	require.NoError(t, err)
	require.NoError(t, es.Refresh(ctx, ts.Index_OrgLevel))

	req := &proto.GetSuggestedFixStatesForOrgRequest{
		OwnerIds:      []uint64{1},
		RepositoryIds: []uint64{1, 2},
	}

	res, err := twirpServ.GetSuggestedFixStatesForOrg(ctx, req)
	require.NoError(t, err)
	require.Len(t, res.SuggestedFixStates, 4)
	require.Equal(t, &proto.RepoSuggestedFixState{
		RepositoryId: 2,
		AlertNumber:  9,
		Eligible:     true,
	}, res.SuggestedFixStates[0])
	require.Equal(t, &proto.RepoSuggestedFixState{
		RepositoryId:   2,
		AlertNumber:    5,
		Eligible:       true,
		State:          proto.SuggestedFixAlertState_SUGGESTED_FIX_ALERT_STATE_ERROR,
		StateUpdatedAt: timestamppb.New(now.Time),
	}, res.SuggestedFixStates[1])
	require.Equal(t, &proto.RepoSuggestedFixState{
		RepositoryId:   1,
		AlertNumber:    2,
		Eligible:       true,
		State:          proto.SuggestedFixAlertState_SUGGESTED_FIX_ALERT_STATE_VALID,
		StateUpdatedAt: timestamppb.New(now.Time),
	}, res.SuggestedFixStates[2])
	require.Equal(t, &proto.RepoSuggestedFixState{
		RepositoryId: 1,
		AlertNumber:  1,
	}, res.SuggestedFixStates[3])
	require.Equal(t, "", res.PrevCursor)
	require.Equal(t, "", res.NextCursor)
}

func TestGetSuggestedFixStatesForOrg_Pagination(t *testing.T) {
	_, ctx, twirpServ, es := setupServiceWithES(t)

	fixedOnDefault := false
	deleted := false
	codeScanningEnabled := true
	now := sqltime.Now()

	var searchDocs []*ts.SearchDocument
	for i := 0; i < 27; i++ {
		searchDocs = append(searchDocs, &ts.SearchDocument{
			OwnerID:               "1",
			RepositoryID:          "1",
			Number:                uint32(i),
			AlertID:               uint64(i),
			CanonicalID:           strconv.FormatInt(int64(i), 10),
			FixedOnDefault:        &fixedOnDefault,
			Deleted:               &deleted,
			CodeScanningEnabled:   &codeScanningEnabled,
			AutofixEligible:       true,
			AutofixState:          ts.SuggestedFixAlertStateValid.DBString(),
			AutofixStateUpdatedAt: &now,
		})
	}

	err := es.IndexDocuments(ctx, ts.Index_OrgLevel, searchDocs)
	require.NoError(t, err)
	require.NoError(t, es.Refresh(ctx, ts.Index_OrgLevel))

	req := &proto.GetSuggestedFixStatesForOrgRequest{
		OwnerIds:      []uint64{1},
		RepositoryIds: []uint64{1, 2},
		Limit:         10,
	}

	firstPage, err := twirpServ.GetSuggestedFixStatesForOrg(ctx, req)
	require.NoError(t, err)
	require.Len(t, firstPage.SuggestedFixStates, 10)
	require.Empty(t, firstPage.PrevCursor)
	require.NotEmpty(t, firstPage.NextCursor)

	req.AfterCursor = firstPage.NextCursor
	secondPage, err := twirpServ.GetSuggestedFixStatesForOrg(ctx, req)
	require.NoError(t, err)
	require.Len(t, secondPage.SuggestedFixStates, 10)
	require.NotEmpty(t, secondPage.PrevCursor)
	require.NotEmpty(t, secondPage.NextCursor)
	require.NotEqual(t, firstPage.PrevCursor, secondPage.PrevCursor)

	req.AfterCursor = secondPage.NextCursor
	thirdPage, err := twirpServ.GetSuggestedFixStatesForOrg(ctx, req)
	require.NoError(t, err)
	require.Len(t, thirdPage.SuggestedFixStates, 7)
	require.NotEmpty(t, thirdPage.PrevCursor)
	require.Empty(t, thirdPage.NextCursor)

	req.AfterCursor = ""
	req.BeforeCursor = thirdPage.PrevCursor
	secondPageFromEnd, err := twirpServ.GetSuggestedFixStatesForOrg(ctx, req)
	require.NoError(t, err)
	require.Equal(t, secondPage.SuggestedFixStates, secondPageFromEnd.SuggestedFixStates)
}

func setupServiceWithES(t *testing.T) (
	*gorm.DB,
	context.Context,
	*Service,
	*elasticsearch.Service,
) {
	t.Helper()
	db := dbtest.RequireConnection(t)
	ctx := context.Background()
	store := store.TestMemoryStore()
	s := sfdb.NewService(db)
	ls := limits.TestLimitSelector()
	as := asdb.TestService(db)
	arch := archiver.NewService(db, store)
	mockAqueduct := &aqueduct.AqueductMock{}
	mockSpokes := &spokes.MockSpokes{}
	sfServ := sf.New(s, as, arch, ls, mockSpokes, sf.NewMockValidFixGenerator())
	es := elasticsearch.SetUpTestElasticSearchService(t)
	twirpSf := New(sfServ, store, mockAqueduct, es)

	return db, ctx, twirpSf, es
}
