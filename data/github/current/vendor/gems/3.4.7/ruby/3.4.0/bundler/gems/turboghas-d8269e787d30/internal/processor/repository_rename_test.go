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

func TestRepositoryRename(t *testing.T) {
	db := dbtest.Seed(t)
	d := dbtest.Data(db)
	ctx := t.Context()

	api := mocks.Cleanup(t, &mockApi{})
	api.On("GetRepositories", mocks.IsContext, &twirpTurboghas.GetRepositoriesRequest{RepositoryIds: []uint64{1}}).Return(&twirpTurboghas.GetRepositoriesResponse{
		Repositories: map[uint64]*twirpTurboghas.GetRepositoriesResponse_Repository{
			1: {
				Entity: &twirpTurboghas.GetRepositoriesResponse_Entity{
					Id:   1,
					Type: twirpTurboghas.EntityType_ENTITY_TYPE_BUSINESS,
				},
				AdvancedSecurityEnabled: int32(v1.Feature_FEATURE_ALL),
				Name:                    "after",
				OwnerId:                 1,
				Owner: &twirpTurboghas.GetUsersResponse_User{
					Login:               "org-1",
					Type:                twirpTurboghas.UserType_USER_TYPE_ORGANIZATION,
					IsEnterpriseManaged: false,
				},
			},
		},
	}, nil).Once()

	msg := &githubv1.RepositoryRename{
		Actor: &entitiesv1.User{
			Login: "ghost",
		},
		Repository: &entitiesv1.Repository{
			Id:         1,
			Visibility: entitiesv1.Repository_PRIVATE,
		},
		PreviousName: "before",
		CurrentName:  "after",
	}

	require.NoError(t, processor.New(d, api, &mockPublisher{}, nil, &mockDeps{}).ProcessMessage(ctx, msg))

	require.Equal(t, "after", dbtest.RequireScan[string](t, db.QueryRow(`SELECT name FROM tg_repositories WHERE repository_id = ? LIMIT 1`, 1)))
}
