package processor_test

import (
	"context"
	"testing"

	advancedSecurityBillingv0 "github.com/github/hydro-schemas-go/hydro/schemas/advanced_security_billing/v0"
	entitiesv1 "github.com/github/hydro-schemas-go/hydro/schemas/github/v1/entities"
	"github.com/github/turboghas/internal/dbtest"
	"github.com/github/turboghas/internal/mocks"
	twirpTurboghas "github.com/github/turboghas/internal/monolith_twirp/turboghas/v1"
	v1 "github.com/github/turboghas/internal/monolith_twirp/turboghas/v1"
	"github.com/github/turboghas/internal/processor"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"
)

func createTwirpRepository(name string, enabled bool) *v1.GetRepositoriesResponse_Repository {
	repo := v1.GetRepositoriesResponse_Repository{
		Entity: &v1.GetRepositoriesResponse_Entity{
			Id:   1,
			Type: v1.EntityType_ENTITY_TYPE_BUSINESS,
		},
		Name:                    name,
		AdvancedSecurityEnabled: enabled,
		Owner: &v1.GetUsersResponse_User{
			Login:               "org-1",
			Type:                v1.UserType_USER_TYPE_ORGANIZATION,
			IsEnterpriseManaged: false,
		},
	}
	return &repo
}

func TestBillingToggled(t *testing.T) {
	db := dbtest.Seed(t)
	d := dbtest.Data(db)
	ctx := context.Background()

	msg := &advancedSecurityBillingv0.BillingToggled{
		Actor: &entitiesv1.User{
			Login: "ghost",
		},
		BillableEntity: &advancedSecurityBillingv0.BillingToggled_Business{
			Business: &entitiesv1.Business{Id: 1},
		},
		ToggleState: false,
	}

	api := mocks.Cleanup(t, &mockApi{})

	api.On("GetRepositories", mocks.IsContext, mock.MatchedBy(mocks.Is[*twirpTurboghas.GetRepositoriesRequest])).Return(&v1.GetRepositoriesResponse{
		Repositories: map[uint64]*v1.GetRepositoriesResponse_Repository{
			1:  createTwirpRepository("enabled-repo-1", true),
			3:  createTwirpRepository("enabled-repo-3", false),
			10: createTwirpRepository("repo-10", true),
		}}, nil).Once()

	deps := mocks.Cleanup(t, &mockDeps{})

	p := processor.New(d, api, nil, nil, deps)

	require.NoError(t, p.ProcessMessage(ctx, msg))

	require.Equal(t, true, dbtest.RequireScan[bool](t, db.QueryRow("SELECT enabled FROM tg_repositories WHERE repository_id = 1")))
	require.Equal(t, false, dbtest.RequireScan[bool](t, db.QueryRow("SELECT enabled FROM tg_repositories WHERE repository_id = 3")))
	require.Equal(t, true, dbtest.RequireScan[bool](t, db.QueryRow("SELECT enabled FROM tg_repositories WHERE repository_id = 10")))
}
