package processor_test

import (
	"testing"

	enterprisev0 "github.com/github/hydro-schemas-go/hydro/schemas/github/enterprise_account/v0"
	entitiesv1 "github.com/github/hydro-schemas-go/hydro/schemas/github/v1/entities"
	"github.com/github/turboghas/internal/dbtest"
	"github.com/github/turboghas/internal/mocks"
	twirpTurboghas "github.com/github/turboghas/internal/monolith_twirp/turboghas/v1"
	"github.com/github/turboghas/internal/processor"
	"github.com/stretchr/testify/require"
)

func TestOrganizationTransfer(t *testing.T) {
	db := dbtest.Seed(t)
	d := dbtest.Data(db)
	ctx := t.Context()

	api := mocks.Cleanup(t, &mockApi{})
	api.On("GetBillableUsers", mocks.IsContext, &twirpTurboghas.GetBillableUsersRequest{OwnerId: 101}).Return(&twirpTurboghas.GetBillableUsersResponse{
		BillableEntityId:   1,
		BillableEntityType: twirpTurboghas.EntityType_ENTITY_TYPE_BUSINESS,
		UserIds:            []uint64{1},
	}, nil).Once()

	msg := &enterprisev0.OrganizationTransfer{
		Actor: &entitiesv1.User{
			Login: "ghost",
		},
		Organization: &entitiesv1.Organization{
			Id: 101,
		},
		DestinationEnterprise: &entitiesv1.Business{
			Id: 102,
		},
	}

	require.NoError(t, processor.New(d, api, &mockPublisher{}, nil, &mockDeps{}).ProcessMessage(ctx, msg))
}
