package processor_test

import (
	"context"
	"testing"

	githubv1 "github.com/github/hydro-schemas-go/hydro/schemas/github/v1"
	entitiesv1 "github.com/github/hydro-schemas-go/hydro/schemas/github/v1/entities"
	"github.com/github/turboghas/internal/dbtest"
	"github.com/github/turboghas/internal/mocks"
	twirpTurboghas "github.com/github/turboghas/internal/monolith_twirp/turboghas/v1"
	"github.com/github/turboghas/internal/processor"
	"github.com/stretchr/testify/require"
)

func TestMembershipUpdate(t *testing.T) {
	db := dbtest.Seed(t)
	d := dbtest.Data(db)
	ctx := context.Background()

	msg := &githubv1.MembershipUpdate{
		Actor: &entitiesv1.User{
			Login: "ghost",
		},
		GroupId: 101,
		Context: githubv1.MembershipUpdate_ORGANIZATION,
	}

	api := mocks.Cleanup(t, &mockApi{})

	p := processor.New(d, api, nil, nil, &mockDeps{})

	api.On("GetBillableUsers", mocks.IsContext, &twirpTurboghas.GetBillableUsersRequest{OwnerId: 101}).Return(&twirpTurboghas.GetBillableUsersResponse{
		BillableEntityId:   1,
		BillableEntityType: twirpTurboghas.EntityType_ENTITY_TYPE_BUSINESS,
		UserIds:            []uint64{1},
	}, nil).Once()

	require.NoError(t, p.ProcessMessage(ctx, msg))
}
