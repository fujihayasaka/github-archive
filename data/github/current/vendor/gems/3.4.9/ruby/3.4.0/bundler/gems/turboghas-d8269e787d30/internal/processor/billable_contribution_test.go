package processor_test

import (
	"testing"
	"time"

	"github.com/github/github-telemetry-go/kvp"
	entitiesv1 "github.com/github/hydro-schemas-go/hydro/schemas/github/v1/entities"
	v0 "github.com/github/hydro-schemas-go/hydro/schemas/turboghas/v0"
	"github.com/github/turboghas/internal/data"
	"github.com/github/turboghas/internal/dbtest"
	"github.com/github/turboghas/internal/fields"
	"github.com/github/turboghas/internal/mocks"
	twirpTurboghas "github.com/github/turboghas/internal/monolith_twirp/turboghas/v1"
	"github.com/github/turboghas/internal/processor"
	"github.com/stretchr/testify/require"
	"github.com/twitchtv/twirp"
	"google.golang.org/protobuf/types/known/timestamppb"
)

func TestBillableContribution(t *testing.T) {
	db := dbtest.RequireConnection(t)
	d := dbtest.Data(db)
	ctx := t.Context()

	msg := &v0.BillableContribution{
		Actor: &entitiesv1.User{
			Login: "ghost",
		},
		Repository: &entitiesv1.Repository{
			Id:         1,
			Visibility: entitiesv1.Repository_PRIVATE,
		},
		Owner: &entitiesv1.User{
			Id:    101,
			Login: "org-1",
			Type:  entitiesv1.User_ORGANIZATION,
		},
		RefUpdates: []*v0.BillableContribution_RefUpdate{
			{RefName: "refs/heads/main", PreviousRefOid: "4d39ee7d0836ac8c17a662685db03a85fa845a4f", CurrentRefOid: "3161860805acb9e11eadfddb6e92274ba00158ac"},
		},
		Committers: []*v0.BillableContribution_Committer{
			{Email: []byte("user@example.com"), Login: "user", UserId: 1},
		},
	}

	api := mocks.Cleanup(t, &mockApi{})
	api.On("GetBillableUsers", mocks.IsContext, &twirpTurboghas.GetBillableUsersRequest{OwnerId: 101}).Return(&twirpTurboghas.GetBillableUsersResponse{
		BillableEntityId:   1,
		BillableEntityType: twirpTurboghas.EntityType_ENTITY_TYPE_BUSINESS,
		UserIds:            []uint64{1},
	}, nil).Once()

	require.NoError(t, processor.New(d, api, nil, nil, &mockDeps{}).ProcessMessage(ctx, msg))

	require.Equal(t, 1, dbtest.RequireScan[int](t, db.QueryRow("SELECT count(1) FROM tg_contributions WHERE user_id = 1")))
}

func TestBillableContributionError(t *testing.T) {
	db := dbtest.RequireConnection(t)
	d := dbtest.Data(db)
	ctx := t.Context()

	msg := &v0.BillableContribution{
		Actor: &entitiesv1.User{
			Login: "ghost",
		},
		Repository: &entitiesv1.Repository{
			Id:         1,
			Visibility: entitiesv1.Repository_PRIVATE,
		},
		Owner: &entitiesv1.User{
			Id:    101,
			Login: "org-1",
			Type:  entitiesv1.User_ORGANIZATION,
		},
		RefUpdates: []*v0.BillableContribution_RefUpdate{
			{RefName: "refs/heads/main", PreviousRefOid: "4d39ee7d0836ac8c17a662685db03a85fa845a4f", CurrentRefOid: "3161860805acb9e11eadfddb6e92274ba00158ac"},
		},
		Committers: []*v0.BillableContribution_Committer{
			{Email: []byte("user@example.com"), Login: "user", UserId: 1},
		},
	}

	api := mocks.Cleanup(t, &mockApi{})
	api.On("GetBillableUsers", mocks.IsContext, &twirpTurboghas.GetBillableUsersRequest{OwnerId: 101}).Return((*twirpTurboghas.GetBillableUsersResponse)(nil), twirp.NewError(twirp.Canceled, "Timed out")).Once()

	err := processor.New(d, api, nil, nil, &mockDeps{}).ProcessMessage(ctx, msg)

	require.Error(t, err)

	require.ElementsMatch(t, fields.From(err), []kvp.Field{kvp.Uint64("gh.org.id", 101)})
}

func TestBillableContributionHasContributorsCache(t *testing.T) {
	db := dbtest.RequireConnection(t)
	d := dbtest.Data(db)
	ctx := t.Context()

	createdAt := time.Now().Add(-10 * time.Minute)

	require.NoError(t, d.UpsertPurchaser(ctx, data.UpsertPurchaserArgs{
		OwnerID:    101,
		EntityType: twirpTurboghas.EntityType_ENTITY_TYPE_BUSINESS,
		EntityID:   1,
	}))

	require.NoError(t, d.UpsertEntity(ctx, data.UpsertEntityArgs{
		EntityType: twirpTurboghas.EntityType_ENTITY_TYPE_BUSINESS,
		EntityID:   1,
		UserIDs:    []uint64{1},
	}))

	msg := &v0.BillableContribution{
		Actor: &entitiesv1.User{
			Login: "ghost",
		},
		Repository: &entitiesv1.Repository{
			Id:         1,
			Visibility: entitiesv1.Repository_PRIVATE,
		},
		Owner: &entitiesv1.User{
			Id:    101,
			Login: "org-1",
			Type:  entitiesv1.User_ORGANIZATION,
		},
		RefUpdates: []*v0.BillableContribution_RefUpdate{
			{RefName: "refs/heads/main", PreviousRefOid: "4d39ee7d0836ac8c17a662685db03a85fa845a4f", CurrentRefOid: "3161860805acb9e11eadfddb6e92274ba00158ac"},
		},
		Committers: []*v0.BillableContribution_Committer{
			{Email: []byte("user@example.com"), Login: "user", UserId: 1, CreatedAt: timestamppb.New(createdAt)},
		},
	}

	require.NoError(t, processor.New(d, &mockApi{}, nil, nil, &mockDeps{}).ProcessMessage(ctx, msg))

	require.Equal(t, 1, dbtest.RequireScan[int](t, db.QueryRow("SELECT count(1) FROM tg_contributions WHERE user_id = 1")))
}
