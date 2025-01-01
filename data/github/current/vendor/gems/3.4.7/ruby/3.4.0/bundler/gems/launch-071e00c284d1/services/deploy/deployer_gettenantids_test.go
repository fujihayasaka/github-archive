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
	"github.com/github/launch/observability/logger"
	"github.com/github/launch/pkg/azp"
	"github.com/github/launch/pkg/schedulemanager"
	pb "github.com/github/launch/services/pb/deploy"
	pbtypes "github.com/github/launch/services/pbtypes"
	"github.com/github/launch/types"
	"github.com/github/launch/workflowbuild/azp/azptypes"

	"github.com/github/launch/observability"
	"github.com/github/launch/services/deploy/workflowinvoker"
)

type getTenantIDsTestSuite struct {
	suite.Suite

	svc *service

	rcf          *azp.MockRepositoryClientFactory
	arr          *deployer.MockAzpResourcesRepository
	rrc          *azp.MockRepositoryClient
	ghtwirp      *ghtwirp.MockClient
	scheduleMngr *schedulemanager.MockManager
}

func TestGetTenantIDsTestSuite(t *testing.T) {
	suite.Run(t, new(getTenantIDsTestSuite))
}

func (s *getTenantIDsTestSuite) SetupTest() {
	s.rcf = &azp.MockRepositoryClientFactory{}
	s.arr = &deployer.MockAzpResourcesRepository{}
	s.rrc = &azp.MockRepositoryClient{}

	s.scheduleMngr = &schedulemanager.MockManager{}
	s.ghtwirp = &ghtwirp.MockClient{}
	s.svc = &service{
		cfg: config{
			Obs:                   observability.NewNullObservability(),
			AqueductQueue:         queueName,
			Log:                   logger.TestLogger(),
			GithubTwirpClient:     s.ghtwirp,
			WorkflowSourceFactory: workflowinvoker.NullWorkflowSourceFactory{},
			ScheduleManager:       s.scheduleMngr,
			AZPResources:          s.arr,
		},
	}
	migrator := deployer.NewGlobalIDMigrator(s.ghtwirp)
	s.svc.gidMigrator = migrator

	s.ghtwirp.On("GetNextGlobalID", mock.Anything, mock.Anything).Return(
		func(ctx context.Context, globalID string) types.GlobalID {
			return types.GlobalID(globalID)
		}, nil)
}

func (s *getTenantIDsTestSuite) TestServiceWillReturnTenantIds() {
	testTenantId := "Test-TenantID"

	s.arr.On("TryGet", mock.Anything, mock.Anything).Return(
		&azptypes.BackingResources{
			CreationResult: azptypes.CreationResult{
				TenantID:    testTenantId,
				TenantName:  "",
				ProjectName: "",
				PipelineID:  0,
				ClientID:    "",
			},
			Environment: "",
			CreatedAt:   &time.Time{},
		},
		nil,
	)

	req := &pb.GetTenantIDsRequest{
		OwnerIds: []*pbtypes.Identity{{
			GlobalId: "GlobalId",
		}},
	}

	res, err := s.svc.GetTenantIds(context.Background(), req)
	s.NotNil(res)
	s.NoError(err)
	s.arr.AssertExpectations(s.T())
	s.rcf.AssertExpectations(s.T())
	s.rrc.AssertExpectations(s.T())
	s.scheduleMngr.AssertExpectations(s.T())
	s.ghtwirp.AssertExpectations(s.T())
	s.Equal(testTenantId, res.TenantIds[0])
}

func (s *getTenantIDsTestSuite) TestServiceWithErrorGettingAzureResources() {
	s.arr.On("TryGet", mock.Anything, mock.Anything).Return(nil, errors.New("error getting azure resources"))

	req := &pb.GetTenantIDsRequest{
		OwnerIds: []*pbtypes.Identity{{
			GlobalId: "GlobalId",
		}},
	}

	res, err := s.svc.GetTenantIds(context.Background(), req)
	s.NotNil(res)
	s.NoError(err)
	s.arr.AssertExpectations(s.T())
	s.rcf.AssertExpectations(s.T())
	s.rrc.AssertExpectations(s.T())
	s.scheduleMngr.AssertExpectations(s.T())
	s.ghtwirp.AssertExpectations(s.T())
	s.Equal("", res.TenantIds[0])
}
