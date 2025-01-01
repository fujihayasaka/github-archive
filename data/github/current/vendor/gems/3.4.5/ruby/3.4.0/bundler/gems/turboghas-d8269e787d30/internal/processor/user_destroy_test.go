package processor_test

import (
	"testing"

	githubv1 "github.com/github/hydro-schemas-go/hydro/schemas/github/v1"
	entitiesv1 "github.com/github/hydro-schemas-go/hydro/schemas/github/v1/entities"
	"github.com/github/turboghas/internal/dbtest"
	"github.com/github/turboghas/internal/mocks"
	twirpTurboghas "github.com/github/turboghas/internal/monolith_twirp/turboghas/v1"
	v1 "github.com/github/turboghas/internal/monolith_twirp/turboghas/v1"
	"github.com/github/turboghas/internal/processor"
	"github.com/stretchr/testify/require"
)

func TestUserDestroy(t *testing.T) {
	db := dbtest.Seed(t)
	d := dbtest.Data(db)
	ctx := t.Context()

	api := mocks.Cleanup(t, &mockApi{})
	api.On("GetUsers", mocks.IsContext, &twirpTurboghas.GetUsersRequest{UserIds: []uint64{1}}).Return(&twirpTurboghas.GetUsersResponse{
		Users: map[uint64]*twirpTurboghas.GetUsersResponse_User{
			1: {
				Login: "after",
				Type:  v1.UserType_USER_TYPE_USER,
			},
		},
	}, nil).Once()

	msg := &githubv1.UserDestroy{
		Actor: &entitiesv1.User{
			Login: "ghost",
		},
		User: &entitiesv1.User{
			Login: "after",
			Id:    1,
		},
	}

	require.NoError(t, processor.New(d, api, &mockPublisher{}, nil, &mockDeps{}).ProcessMessage(ctx, msg))

	require.Equal(t, "after", dbtest.RequireScan[string](t, db.QueryRow(`SELECT login FROM tg_users WHERE user_id = ? LIMIT 1`, 1)))
}
