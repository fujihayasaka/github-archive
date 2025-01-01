package processor_test

import (
	"testing"

	githubv1 "github.com/github/hydro-schemas-go/hydro/schemas/github/v1"
	entitiesv1 "github.com/github/hydro-schemas-go/hydro/schemas/github/v1/entities"
	"github.com/github/turboghas/internal/data"
	"github.com/github/turboghas/internal/dbtest"
	"github.com/github/turboghas/internal/mocks"
	twirpTurboghas "github.com/github/turboghas/internal/monolith_twirp/turboghas/v1"
	v1 "github.com/github/turboghas/internal/monolith_twirp/turboghas/v1"
	"github.com/github/turboghas/internal/processor"
	"github.com/stretchr/testify/require"
)

func TestRepositoryRestored(t *testing.T) {
	db := dbtest.Seed(t)
	d := dbtest.Data(db)
	ctx := t.Context()

	require.NoError(t, d.UpsertRepository(ctx, data.UpsertRepositoryArgs{
		RepositoryID: 1,
		OwnerID:      1,
		Name:         "before",
		Enabled:      data.Feature(v1.Feature_FEATURE_ALL),
	}))
	require.NoError(t, d.DeleteRepository(ctx, 1))

	require.Zero(t, dbtest.RequireScan[int](t, db.QueryRow(`SELECT COUNT(1) FROM tg_repositories WHERE repository_id = ?`, 1)))

	api := mocks.Cleanup(t, &mockApi{})
	api.On("GetRepositories", mocks.IsContext, &twirpTurboghas.GetRepositoriesRequest{RepositoryIds: []uint64{1}}).Return(&twirpTurboghas.GetRepositoriesResponse{
		Repositories: map[uint64]*twirpTurboghas.GetRepositoriesResponse_Repository{
			1: {
				Entity: &twirpTurboghas.GetRepositoriesResponse_Entity{
					Id:   1,
					Type: twirpTurboghas.EntityType_ENTITY_TYPE_BUSINESS,
				},
				Name:    "test",
				OwnerId: 1,
				Owner: &twirpTurboghas.GetUsersResponse_User{
					Login:               "org-1",
					Type:                twirpTurboghas.UserType_USER_TYPE_ORGANIZATION,
					IsEnterpriseManaged: false,
				},
			},
		},
	}, nil).Once()

	msg := &githubv1.RepositoryRestored{
		Actor: &entitiesv1.User{
			Login: "ghost",
		},
		RestoredRepository: &entitiesv1.Repository{
			Id:         1,
			Visibility: entitiesv1.Repository_PRIVATE,
		},
	}

	require.NoError(t, processor.New(d, api, &mockPublisher{}, nil, &mockDeps{}).ProcessMessage(ctx, msg))

	require.Equal(t, 1, dbtest.RequireScan[int](t, db.QueryRow(`SELECT COUNT(1) FROM tg_repositories WHERE repository_id = ?`, 1)))
}
