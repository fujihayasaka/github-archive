package selfhostedrunners

import (
	context "context"
	"testing"

	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/suite"

	errs "github.com/pkg/errors"

	"github.com/github/launch/db/stores/deployer"
	"github.com/github/launch/observability/logger"
	"github.com/github/launch/observability/statter"
	"github.com/github/launch/pkg/azp"
	svcerr "github.com/github/launch/services/errors"
	pbtypes "github.com/github/launch/services/pbtypes"
	"github.com/github/launch/types"
	"github.com/github/launch/workflowbuild/azp/azptypes"
)

type getAccessPolicyTestSuite struct {
	suite.Suite

	svc *service

	rcf *azp.MockRepositoryClientFactory
	arr *deployer.MockAzpResourcesRepository
	rrc *azp.MockRepositoryClient
}

func TestGetAccessPolicyTestSuite(t *testing.T) {
	suite.Run(t, new(getAccessPolicyTestSuite))
}

func (s *getAccessPolicyTestSuite) SetupTest() {
	s.rcf = &azp.MockRepositoryClientFactory{}
	s.arr = &deployer.MockAzpResourcesRepository{}
	s.rrc = &azp.MockRepositoryClient{}
	s.svc = &service{
		log:                  logger.TestLogger(),
		stats:                statter.NullStatter(),
		azpRepoClientFactory: s.rcf,
		azpResourceRepo:      s.arr,
	}
}

func (s *getAccessPolicyTestSuite) Test_ServiceWillReturnAccessPolicy() {
	accessPolicy := s.getMockAccessPolicy()

	s.arr.On("TryGet", mock.Anything, mock.Anything).Return(&azptypes.BackingResources{}, nil)
	s.rcf.On("ClientFromResources", mock.Anything, mock.Anything).Return(s.rrc)
	s.rrc.On("GetAccessPolicy", mock.Anything).Return(accessPolicy, nil)

	req := &GetAccessPolicyRequest{
		OwnerId: &pbtypes.Identity{
			GlobalId: "GlobalId",
		},
	}

	expectedRepositoryIdentities := types.IdentitiesFromGlobalIDs(accessPolicy.SelectedRepositories)

	res, err := s.svc.GetAccessPolicy(context.TODO(), req)
	s.NotNil(res)
	s.NoError(err)
	s.arr.AssertExpectations(s.T())
	s.rcf.AssertExpectations(s.T())
	s.rrc.AssertExpectations(s.T())
	s.Equal(PermissionType_SELECTED_REPOSITORIES, res.GetPermissionType())
	s.Equal(expectedRepositoryIdentities, res.GetSelectedRepositories())
}

func (s *getAccessPolicyTestSuite) Test_ServiceFailsWithInvalidGlobalID() {
	req := &GetAccessPolicyRequest{
		OwnerId: &pbtypes.Identity{
			GlobalId: "",
		},
	}

	res, err := s.svc.GetAccessPolicy(context.TODO(), req)
	s.Nil(res)
	s.Error(err)
	s.Equal(err, svcerr.NewInvalidArgumentError("owner id cannot be nil"))
}

func (s *getAccessPolicyTestSuite) Test_ServiceFailsWithBadRepositoryClient() {

	s.arr.On("TryGet", mock.Anything, mock.Anything).Return(nil, errs.New("error!"))

	req := &GetAccessPolicyRequest{
		OwnerId: &pbtypes.Identity{
			GlobalId: "GlobalId",
		},
	}

	res, err := s.svc.GetAccessPolicy(context.TODO(), req)
	s.Nil(res)
	s.Error(err)
	s.Equal(err, svcerr.NewInvalidArgumentError("unable to create azp resource client for repository: error!"))
	s.arr.AssertExpectations(s.T())
}

func (s *getAccessPolicyTestSuite) Test_ServiceFailsWithBadCredentials() {

	s.arr.On("TryGet", mock.Anything, mock.Anything).Return(&azptypes.BackingResources{}, nil)
	s.rcf.On("ClientFromResources", mock.Anything, mock.Anything).Return(s.rrc)
	s.rrc.On("GetAccessPolicy", mock.Anything).Return(nil, errs.New("error!"))

	req := &GetAccessPolicyRequest{
		OwnerId: &pbtypes.Identity{
			GlobalId: "GlobalId",
		},
	}

	res, err := s.svc.GetAccessPolicy(context.TODO(), req)
	s.Nil(res)
	s.Error(err)
	s.arr.AssertExpectations(s.T())
	s.rcf.AssertExpectations(s.T())
	s.rrc.AssertExpectations(s.T())
}

func (s *getAccessPolicyTestSuite) getMockAccessPolicy() *azp.AccessPolicy {
	var repoGlobalIds = []types.GlobalID{"abc123", "abd123"}
	return &azp.AccessPolicy{
		PermissionType:       "selectedRepos",
		SelectedRepositories: repoGlobalIds,
	}
}
