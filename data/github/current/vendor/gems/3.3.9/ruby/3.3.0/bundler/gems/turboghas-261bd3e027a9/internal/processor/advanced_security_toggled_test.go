package processor_test

import (
	"context"
	"testing"

	securitycenterv0 "github.com/github/hydro-schemas-go/hydro/schemas/github/security_center/v0"
	"github.com/github/turboghas/internal/dbtest"
	"github.com/github/turboghas/internal/mocks"
	twirpTurboghas "github.com/github/turboghas/internal/monolith_twirp/turboghas/v1"
	"github.com/github/turboghas/internal/processor"
	"github.com/stretchr/testify/require"
)

func TestAdvancedSecurityToggled(t *testing.T) {
	db := dbtest.Seed(t)
	d := dbtest.Data(db)
	ctx := context.Background()

	api := mocks.Cleanup(t, &mockApi{})
	api.On("GetRepositories", mocks.IsContext, &twirpTurboghas.GetRepositoriesRequest{RepositoryIds: []uint64{2}}).Return(&twirpTurboghas.GetRepositoriesResponse{
		Repositories: map[uint64]*twirpTurboghas.GetRepositoriesResponse_Repository{
			2: {
				Entity: &twirpTurboghas.GetRepositoriesResponse_Entity{
					Id:   2,
					Type: twirpTurboghas.EntityType_ENTITY_TYPE_BUSINESS,
				},
				AdvancedSecurityEnabled: true,
				Name:                    "repo-2",
				OwnerId:                 1,
				Owner: &twirpTurboghas.GetUsersResponse_User{
					Login:               "org-1",
					Type:                twirpTurboghas.UserType_USER_TYPE_ORGANIZATION,
					IsEnterpriseManaged: false,
				},
			},
		},
	}, nil).Once()

	msg := &securitycenterv0.AdvancedSecurityToggled{
		RepositoryId:   2,
		FeatureEnabled: true,
	}

	require.NoError(t, processor.New(d, api, &mockPublisher{}, nil, &mockDeps{}).ProcessMessage(ctx, msg))

	require.True(t, dbtest.RequireScan[bool](t, db.QueryRow(`SELECT enabled FROM tg_repositories WHERE repository_id = ? LIMIT 1`, 2)))
}
