package deploy

import (
	"context"
	"testing"
	"time"

	"github.com/pkg/errors"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/suite"

	"github.com/github/launch/clients/ghtwirp"
	"github.com/github/launch/db/stores/deployer"
	"github.com/github/launch/observability"
	"github.com/github/launch/observability/logger"
	"github.com/github/launch/observability/statter"
	svcerr "github.com/github/launch/services/errors"
	pb "github.com/github/launch/services/pb/deploy"
	"github.com/github/launch/services/pbtypes"
	"github.com/github/launch/types"
	"github.com/github/launch/workerpool"
	"github.com/github/launch/workflowbuild/azp"
)

func TestDeployer_SetupTenant(t *testing.T) {
	suite.Run(t, new(SetupTenantSuite))
}

type SetupTenantSuite struct {
	suite.Suite
	svc           *service
	th            *azp.MockTenantHandler
	ghtwirpClient *ghtwirp.MockClient
}

func (s *SetupTenantSuite) SetupTest() {
	log := logger.TestLogger()
	nullStatter := statter.NullStatter()
	s.th = &azp.MockTenantHandler{}
	s.ghtwirpClient = &ghtwirp.MockClient{}

	s.svc = &service{
		cfg: config{
			Log:               log,
			Stats:             nullStatter,
			Obs:               observability.NewNullObservability(),
			TenantHandler:     s.th,
			Workers:           workerpool.NewSimple(log, nullStatter),
			GithubTwirpClient: s.ghtwirpClient,
		},
		gidMigrator: deployer.NewGlobalIDMigrator(s.ghtwirpClient),
	}

	s.ghtwirpClient.On("GetNextGlobalID", mock.Anything, mock.Anything).Return(
		func(ctx context.Context, globalID string) types.GlobalID {
			if globalID == "" {
				return types.NilGlobalID
			}
			return types.GlobalID(globalID)
		}, nil)
}

func (s *SetupTenantSuite) Test_MissingArgs() {
	ctx := context.Background()
	_, err := s.svc.SetupTenant(ctx, &pb.SetupTenantRequest{})
	s.Error(err)
}

func (s *SetupTenantSuite) Test_Success() {
	s.th.On(
		"GetOrCreateTenant",
		mock.Anything,
		types.GlobalID("R_tenant-id"),
		types.GlobalID("O_owner-tenant-id"),
	).Return(deployer.OrgCreationSuccess, nil)

	res, err := s.svc.SetupTenant(context.Background(), &pb.SetupTenantRequest{
		GlobalRelayId:      &pbtypes.Identity{GlobalId: "R_tenant-id"},
		OwnerGlobalRelayId: &pbtypes.Identity{GlobalId: "O_owner-tenant-id"},
		TimeoutMs:          100,
	})

	s.NoError(err)
	s.Empty(res.GetError())
	s.Equal("success", res.GetStatus())
	s.svc.cfg.Workers.Stop()
	s.th.AssertExpectations(s.T())
}

func (s *SetupTenantSuite) Test_SuccessWithoutTimeoutIgnoresErrors() {
	s.th.On(
		"GetOrCreateTenant",
		mock.Anything,
		types.GlobalID("R_tenant-id"),
		types.NilGlobalID,
	).Return(deployer.OrgCreationError, errors.New("test"))

	res, err := s.svc.SetupTenant(context.Background(), &pb.SetupTenantRequest{
		GlobalRelayId: &pbtypes.Identity{GlobalId: "R_tenant-id"},
	})

	s.NoError(err)
	s.Empty(res.GetError())
	s.Equal("success", res.GetStatus())
	s.svc.cfg.Workers.Stop()
	s.th.AssertExpectations(s.T())
}

func (s *SetupTenantSuite) Test_SyncronousUnsuccessful() {
	s.th.On(
		"GetOrCreateTenant",
		mock.Anything,
		types.GlobalID("R_tenant-id"),
		types.NilGlobalID,
	).Return(deployer.OrgCreationError, errors.New("test"))

	res, err := s.svc.SetupTenant(context.Background(), &pb.SetupTenantRequest{
		GlobalRelayId: &pbtypes.Identity{GlobalId: "R_tenant-id"},
		TimeoutMs:     100,
	})

	s.Nil(res)
	s.Equal(svcerr.NewInternalError("error setting up tenant"), err)
	s.svc.cfg.Workers.Stop()
	s.th.AssertExpectations(s.T())
}

func (s *SetupTenantSuite) Test_BadArgs() {
	res, err := s.svc.SetupTenant(context.Background(), &pb.SetupTenantRequest{
		GlobalRelayId: &pbtypes.Identity{GlobalId: ""},
	})

	s.Nil(res)
	s.Error(err)
	s.Contains(err.Error(), "global id cannot be nil")
}

func (s *SetupTenantSuite) Test_SyncronousTimeout() {
	s.th.On(
		"GetOrCreateTenant",
		mock.Anything,
		types.GlobalID("R_tenant-id"),
		types.NilGlobalID,
	).
		After(time.Millisecond*2).
		Return(deployer.OrgCreationSuccess, nil)

	res, err := s.svc.SetupTenant(context.Background(), &pb.SetupTenantRequest{
		GlobalRelayId: &pbtypes.Identity{GlobalId: "R_tenant-id"},
		TimeoutMs:     1,
	})

	s.Nil(res)
	s.Equal(svcerr.NewDeadlineExceededError("deadline of 1 exceeded during tenant creation"), err)
	s.svc.cfg.Workers.Stop()
	s.th.AssertExpectations(s.T())
}
