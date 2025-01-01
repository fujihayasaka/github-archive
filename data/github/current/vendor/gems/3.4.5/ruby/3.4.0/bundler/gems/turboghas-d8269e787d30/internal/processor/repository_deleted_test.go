package processor_test

import (
	"testing"

	githubv1 "github.com/github/hydro-schemas-go/hydro/schemas/github/v1"
	entitiesv1 "github.com/github/hydro-schemas-go/hydro/schemas/github/v1/entities"
	"github.com/github/turboghas/internal/dbtest"
	"github.com/github/turboghas/internal/mocks"
	twirpTurboghas "github.com/github/turboghas/internal/monolith_twirp/turboghas/v1"
	"github.com/github/turboghas/internal/processor"
	"github.com/stretchr/testify/require"
)

func TestRepositoryDeleted(t *testing.T) {
	db := dbtest.Seed(t)
	d := dbtest.Data(db)
	ctx := t.Context()

	api := mocks.Cleanup(t, &mockApi{})
	api.On("GetRepositories", mocks.IsContext, &twirpTurboghas.GetRepositoriesRequest{RepositoryIds: []uint64{1}}).
		Return((*twirpTurboghas.GetRepositoriesResponse)(nil), nil).
		Once()

	msg := &githubv1.RepositoryDeleted{
		Actor: &entitiesv1.User{
			Login: "ghost",
		},
		DeletedRepository: &entitiesv1.Repository{
			Id:         1,
			Visibility: entitiesv1.Repository_PRIVATE,
		},
	}

	require.NoError(t, processor.New(d, api, &mockPublisher{}, nil, &mockDeps{}).ProcessMessage(ctx, msg))
}
