package main

import (
	"context"
	"testing"

	"github.com/github/turboghas/internal/dbtest"
	"github.com/github/turboghas/internal/mocks"
	twirpTurboghas "github.com/github/turboghas/internal/monolith_twirp/turboghas/v1"
	v1 "github.com/github/turboghas/internal/monolith_twirp/turboghas/v1"
	"github.com/github/turboghas/internal/resync"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"
)

type mockApi struct {
	mock.Mock
}

// this is so that gopls can help us generate the missing mock methods.
var _ v1.TurboghasAPI = &mockApi{}

// GetEntities implements v1.TurboghasAPI.
func (m *mockApi) GetEntities(ctx context.Context, request *v1.GetEntitiesRequest) (*v1.GetEntitiesResponse, error) {
	args := m.Called(ctx, request)
	return args.Get(0).(*twirpTurboghas.GetEntitiesResponse), args.Error(1)
}

// GetRepositories implements v1.TurboghasAPI.
func (m *mockApi) GetRepositories(ctx context.Context, request *v1.GetRepositoriesRequest) (*v1.GetRepositoriesResponse, error) {
	args := m.Called(ctx, request)
	return args.Get(0).(*twirpTurboghas.GetRepositoriesResponse), args.Error(1)
}

// GetUsers implements v1.TurboghasAPI.
func (m *mockApi) GetUsers(ctx context.Context, request *v1.GetUsersRequest) (*v1.GetUsersResponse, error) {
	args := m.Called(ctx, request)
	return args.Get(0).(*twirpTurboghas.GetUsersResponse), args.Error(1)
}

func (m *mockApi) FindUsersByEmails(ctx context.Context, request *twirpTurboghas.FindUsersByEmailsRequest) (*twirpTurboghas.FindUsersByEmailsResponse, error) {
	args := m.Called(ctx, request)
	return args.Get(0).(*twirpTurboghas.FindUsersByEmailsResponse), args.Error(1)
}

func (m *mockApi) GetBillableUsers(ctx context.Context, request *twirpTurboghas.GetBillableUsersRequest) (*twirpTurboghas.GetBillableUsersResponse, error) {
	args := m.Called(ctx, request)
	return args.Get(0).(*twirpTurboghas.GetBillableUsersResponse), args.Error(1)
}

func TestSync(t *testing.T) {
	db := dbtest.Seed(t)

	ctx := context.Background()

	{
		_, err := db.Exec(`UPDATE tg_repositories SET updated_at = NOW() - INTERVAL 8 DAY`)
		require.NoError(t, err)
	}
	{
		_, err := db.Exec(`UPDATE tg_users SET updated_at = NOW() - INTERVAL 8 DAY`)
		require.NoError(t, err)
	}
	{
		_, err := db.Exec(`UPDATE tg_entities SET updated_at = NOW() - INTERVAL 8 DAY`)
		require.NoError(t, err)
	}

	api := mocks.Cleanup(t, &mockApi{})
	api.On("GetUsers", mocks.IsContext, mock.MatchedBy(mocks.Is[*twirpTurboghas.GetUsersRequest])).Return(&twirpTurboghas.GetUsersResponse{
		Users: map[uint64]*v1.GetUsersResponse_User{
			1: {
				Login: "name",
				Type:  v1.UserType_USER_TYPE_USER,
			},
			3: {
				Login: "some_other_name",
				Type:  v1.UserType_USER_TYPE_USER,
			},
		},
	}, nil).Times(1)
	api.On("GetRepositories", mocks.IsContext, mock.MatchedBy(mocks.Is[*twirpTurboghas.GetRepositoriesRequest])).Return(&twirpTurboghas.GetRepositoriesResponse{
		Repositories: map[uint64]*v1.GetRepositoriesResponse_Repository{
			1: {
				Entity: &v1.GetRepositoriesResponse_Entity{
					Id:   1,
					Type: twirpTurboghas.EntityType_ENTITY_TYPE_BUSINESS,
				},
				Name:                    "test-renamed",
				AdvancedSecurityEnabled: true,
				Owner: &twirpTurboghas.GetUsersResponse_User{
					Login:               "test",
					Type:                twirpTurboghas.UserType_USER_TYPE_ORGANIZATION,
					IsEnterpriseManaged: false,
				},
			},
		},
	}, nil).Times(1)
	api.On("GetEntities", mocks.IsContext, mock.MatchedBy(mocks.Is[*twirpTurboghas.GetEntitiesRequest])).Return(&twirpTurboghas.GetEntitiesResponse{
		Entities: []*twirpTurboghas.GetEntitiesResponse_Entity{
			{Id: 1, Type: v1.EntityType_ENTITY_TYPE_BUSINESS, UserIds: []uint64{1}},
		},
	}, nil).Times(1)

	rs := resync.New(dbtest.Data(db), api)

	require.NoError(t, syncDataWithMonolith(ctx, dbtest.Dual(db), rs, 1))

	require.Zero(t, dbtest.RequireScan[int](t, db.QueryRow(`SELECT COUNT(1) FROM tg_repositories WHERE updated_at + INTERVAL 7 DAY < NOW()`)))
	require.Zero(t, dbtest.RequireScan[int](t, db.QueryRow(`SELECT COUNT(*) FROM tg_repositories WHERE repository_id != 1`)))
	require.Equal(t, 1, dbtest.RequireScan[int](t, db.QueryRow(`SELECT COUNT(*) FROM tg_repositories WHERE repository_id = 1`)))
	// Check the user with id 2 is deleted
	require.Zero(t, dbtest.RequireScan[int](t, db.QueryRow(`SELECT COUNT(*) FROM tg_users WHERE user_id = 2`)))
	require.Zero(t, dbtest.RequireScan[int](t, db.QueryRow(`SELECT COUNT(1) FROM tg_users WHERE type = 'User' AND updated_at + INTERVAL 7 DAY < NOW()`)))
	require.Zero(t, dbtest.RequireScan[int](t, db.QueryRow(`SELECT COUNT(1) FROM tg_entities WHERE updated_at + INTERVAL 7 DAY < NOW()`)))
	require.Equal(t, 1, dbtest.RequireScan[int](t, db.QueryRow(`SELECT COUNT(1) FROM tg_entities`)))
}

func TestDeleteStaleContributions(t *testing.T) {
	db := dbtest.Seed(t)

	// seed includes 1 old commit
	count := dbtest.RequireScan[int](t, db.QueryRow(`SELECT COUNT(1) FROM tg_contributions`))

	ctx := context.Background()

	require.NoError(t, deleteStaleData(ctx, dbtest.Dual(db)))

	// old commit should be deleted
	require.Equal(t, count-1, dbtest.RequireScan[int](t, db.QueryRow(`SELECT COUNT(1) FROM tg_contributions`)))
}
