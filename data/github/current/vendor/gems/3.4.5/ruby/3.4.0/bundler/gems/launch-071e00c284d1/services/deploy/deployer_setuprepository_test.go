package deploy

import (
	"context"
	"testing"

	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/suite"

	"github.com/github/launch/clients/ghtwirp"
	"github.com/github/launch/db/stores/deployer"
	"github.com/github/launch/observability"
	"github.com/github/launch/observability/logger"
	"github.com/github/launch/observability/statter"
	pb "github.com/github/launch/services/pb/deploy"
	"github.com/github/launch/services/pbtypes"
	"github.com/github/launch/types"
	"github.com/github/launch/workerpool"
	"github.com/github/launch/workflowbuild/azp"
)

func TestDeployer_SetupRepository(t *testing.T) {
	suite.Run(t, new(SetupRepositorySuite))
}

type SetupRepositorySuite struct {
	suite.Suite
	svc           *service
	th            *azp.MockTenantHandler
	ghtwirpClient *ghtwirp.MockClient
}

func (s *SetupRepositorySuite) SetupTest() {
	log := logger.TestLogger()
	nullStatter := statter.NullStatter()
	s.th = &azp.MockTenantHandler{}
	s.ghtwirpClient = &ghtwirp.MockClient{}

	s.svc = &service{
		cfg: config{
			Log:               log,
			Stats:             nullStatter,
			Obs:               observability.New(log, nullStatter),
			TenantHandler:     s.th,
			Workers:           workerpool.NewSimple(log, nullStatter),
			GithubTwirpClient: s.ghtwirpClient,
		},
	}
	migrator := deployer.NewGlobalIDMigrator(s.ghtwirpClient)
	s.svc.gidMigrator = migrator
}

func (s *SetupRepositorySuite) Test_MissingArgs() {
	s.ghtwirpClient.On("GetNextGlobalID", mock.Anything, "").Return(types.NilGlobalID, nil)
	ctx := context.Background()
	_, err := s.svc.SetupRepository(ctx, &pb.SetupRepositoryRequest{})
	s.Error(err)
}

func (s *SetupRepositorySuite) Test_Success() {
	s.ghtwirpClient.On("GetNextGlobalID", mock.Anything, mock.Anything).Return(
		func(ctx context.Context, globalID string) types.GlobalID {
			return types.GlobalID(globalID)
		}, nil)

	s.th.On(
		"GetOrCreateTenants",
		mock.Anything,
		types.GlobalID("R_repo-id"),
		types.GlobalID("O_owner-id"),
		types.GlobalID("O_plan-owner-id"),
		types.RepositoryFullName{Name: "repo-name", Owner: "repo-owner"},
	).Return(nil, nil, deployer.OrgCreationSuccess, nil)

	res, err := s.svc.SetupRepository(context.Background(), &pb.SetupRepositoryRequest{
		RepositoryId: &pbtypes.Identity{GlobalId: "R_repo-id"},
		OwnerId:      &pbtypes.Identity{GlobalId: "O_owner-id"},
		PlanOwnerId:  &pbtypes.Identity{GlobalId: "O_plan-owner-id"},
		Name:         "repo-name",
		Owner:        "repo-owner",
	})

	s.NoError(err)
	s.Empty(res.GetError())
	s.Equal("success", res.GetStatus())
	s.svc.cfg.Workers.Stop()
	s.th.AssertExpectations(s.T())
}

func (s *SetupRepositorySuite) Test_BadArgs() {
	s.ghtwirpClient.On("GetNextGlobalID", mock.Anything, "").Return(types.NilGlobalID, nil)
	res, err := s.svc.SetupRepository(context.Background(), &pb.SetupRepositoryRequest{
		RepositoryId: &pbtypes.Identity{GlobalId: ""},
		OwnerId:      &pbtypes.Identity{GlobalId: "O_owner-id"},
		PlanOwnerId:  &pbtypes.Identity{GlobalId: "O_plan-owner-id"},
		Name:         "repo-name",
		Owner:        "repo-owner",
	})

	s.Nil(res)
	s.Error(err)
	s.Contains(err.Error(), "repo id cannot be nil")
}
