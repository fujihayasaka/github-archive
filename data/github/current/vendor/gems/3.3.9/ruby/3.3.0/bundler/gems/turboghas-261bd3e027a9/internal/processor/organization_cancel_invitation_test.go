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

func TestOrganizationCancelInvitation(t *testing.T) {
	db := dbtest.Seed(t)
	d := dbtest.Data(db)
	ctx := context.Background()

	api := mocks.Cleanup(t, &mockApi{})
	api.On("GetBillableUsers", mocks.IsContext, &twirpTurboghas.GetBillableUsersRequest{OwnerId: 101}).Return(&twirpTurboghas.GetBillableUsersResponse{
		BillableEntityId:   1,
		BillableEntityType: twirpTurboghas.EntityType_ENTITY_TYPE_BUSINESS,
		UserIds:            []uint64{1},
	}, nil).Once()

	msg := &githubv1.OrganizationCancelInvitation{
		Actor: &entitiesv1.User{
			Login: "ghost",
		},
		Organization: &entitiesv1.Organization{
			Id: 101,
		},
	}

	require.NoError(t, processor.New(d, api, &mockPublisher{}, nil, &mockDeps{}).ProcessMessage(ctx, msg))
}
