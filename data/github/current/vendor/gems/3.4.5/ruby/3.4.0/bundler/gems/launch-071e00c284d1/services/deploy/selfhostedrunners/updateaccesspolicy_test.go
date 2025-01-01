package selfhostedrunners

import (
	context "context"
	"testing"

	errs "github.com/pkg/errors"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/suite"

	"github.com/github/launch/db/stores/deployer"
	"github.com/github/launch/observability/logger"
	"github.com/github/launch/observability/statter"
	"github.com/github/launch/pkg/azp"
	svcerr "github.com/github/launch/services/errors"
	pbtypes "github.com/github/launch/services/pbtypes"
	"github.com/github/launch/types"
	"github.com/github/launch/workflowbuild/azp/azptypes"
)

type updateAccessPolicyTestSuite struct {
	suite.Suite

	svc *service

	rcf *azp.MockRepositoryClientFactory
	arr *deployer.MockAzpResourcesRepository
	rrc *azp.MockRepositoryClient
}

func TestUpdateAccessPolicyTestSuite(t *testing.T) {
	suite.Run(t, new(updateAccessPolicyTestSuite))
}

func (s *updateAccessPolicyTestSuite) SetupTest() {
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

func (s *updateAccessPolicyTestSuite) Test_ServiceWillReturnAccessPolicy() {
	accessPolicy := s.getMockAccessPolicy()
	existingAccessPolicy := s.getMockExistingAccessPolicy()

	s.arr.On("TryGet", mock.Anything, mock.Anything).Return(&azptypes.BackingResources{}, nil)
	s.rcf.On("ClientFromResources", mock.Anything, mock.Anything).Return(s.rrc)
	s.rrc.On("UpdateAccessPolicy", mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(accessPolicy, nil)
	s.rrc.On("GetAccessPolicy", mock.Anything, mock.Anything, mock.Anything).Return(existingAccessPolicy, nil)

	req := &UpdateAccessPolicyRequest{
		OwnerId: &pbtypes.Identity{
			GlobalId: "GlobalId",
		},
		PermissionType:       0,
		SelectedRepositories: s.getMockSelectedRepos(),
	}

	expectedRepositoryIdentities := types.IdentitiesFromGlobalIDs(accessPolicy.SelectedRepositories)

	res, err := s.svc.UpdateAccessPolicy(context.TODO(), req)
	s.NotNil(res)
	s.NoError(err)
	s.arr.AssertExpectations(s.T())
	s.rcf.AssertExpectations(s.T())
	s.rrc.AssertExpectations(s.T())
	s.Equal(PermissionType_SELECTED_REPOSITORIES, res.GetPermissionType())
	s.Equal(expectedRepositoryIdentities, res.GetSelectedRepositories())
}

func (s *updateAccessPolicyTestSuite) Test_ServiceWillRemoveUnusedRepos() {
	accessPolicy := s.getMockAccessPolicy()

	var repoGlobalIds = []types.GlobalID{"abc123", "abd123", "to-be-removed"}
	existingAccessPolicy := &azp.AccessPolicy{
		PermissionType:       "selected-repos",
		SelectedRepositories: repoGlobalIds,
	}

	expectedReplaceOp := azp.PermissionOp{
		Op:    "replace",
		Path:  "/permissionType",
		Value: "selectedRepos",
	}

	expectedRemoveOp := azp.SelectedReposOp{
		Op:    "remove",
		Path:  "/selectedRepositories",
		Value: []types.GlobalID{"to-be-removed"},
	}

	s.arr.On("TryGet", mock.Anything, mock.Anything).Return(&azptypes.BackingResources{}, nil)
	s.rcf.On("ClientFromResources", mock.Anything, mock.Anything).Return(s.rrc)
	s.rrc.On("UpdateAccessPolicy", mock.Anything, expectedReplaceOp, mock.Anything, expectedRemoveOp).Return(accessPolicy, nil)
	s.rrc.On("GetAccessPolicy", mock.Anything, mock.Anything, mock.Anything).Return(existingAccessPolicy, nil)

	req := &UpdateAccessPolicyRequest{
		OwnerId: &pbtypes.Identity{
			GlobalId: "GlobalId",
		},
		PermissionType:       2,
		SelectedRepositories: s.getMockSelectedRepos(),
	}

	expectedRepositoryIdentities := types.IdentitiesFromGlobalIDs(accessPolicy.SelectedRepositories)

	res, err := s.svc.UpdateAccessPolicy(context.TODO(), req)
	s.NotNil(res)
	s.NoError(err)
	s.arr.AssertExpectations(s.T())
	s.rcf.AssertExpectations(s.T())
	s.rrc.AssertExpectations(s.T())
	s.Equal(PermissionType_SELECTED_REPOSITORIES, res.GetPermissionType())
	s.Equal(expectedRepositoryIdentities, res.GetSelectedRepositories())
}

func (s *updateAccessPolicyTestSuite) Test_ServiceFailsWithInvalidGlobalID() {
	req := &UpdateAccessPolicyRequest{
		OwnerId: &pbtypes.Identity{
			GlobalId: "",
		},
		PermissionType:       0,
		SelectedRepositories: s.getMockSelectedRepos(),
	}

	res, err := s.svc.UpdateAccessPolicy(context.TODO(), req)
	s.Nil(res)
	s.Error(err)
	s.Equal(err, svcerr.NewInvalidArgumentError("owner id cannot be nil"))
}

func (s *updateAccessPolicyTestSuite) Test_ServiceFailsWithBadRepositoryClient() {
	s.arr.On("TryGet", mock.Anything, mock.Anything).Return(nil, errs.New("error!"))

	req := &UpdateAccessPolicyRequest{
		OwnerId: &pbtypes.Identity{
			GlobalId: "GlobalId",
		},
		PermissionType:       0,
		SelectedRepositories: s.getMockSelectedRepos(),
	}

	res, err := s.svc.UpdateAccessPolicy(context.TODO(), req)
	s.Nil(res)
	s.Error(err)
	s.Equal(err, svcerr.NewInvalidArgumentError("unable to create azp resource client for repository: error!"))
	s.arr.AssertExpectations(s.T())
}

func (s *updateAccessPolicyTestSuite) Test_ServiceFailsWithBadCredentials() {

	s.arr.On("TryGet", mock.Anything, mock.Anything).Return(&azptypes.BackingResources{}, nil)
	s.rcf.On("ClientFromResources", mock.Anything, mock.Anything).Return(s.rrc)
	s.rrc.On("UpdateAccessPolicy", mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(nil, errs.New("error!"))
	s.rrc.On("GetAccessPolicy", mock.Anything, mock.Anything, mock.Anything).Return(s.getMockAccessPolicy(), nil)

	req := &UpdateAccessPolicyRequest{
		OwnerId: &pbtypes.Identity{
			GlobalId: "GlobalId",
		},
		PermissionType:       0,
		SelectedRepositories: s.getMockSelectedRepos(),
	}

	res, err := s.svc.UpdateAccessPolicy(context.TODO(), req)
	s.Nil(res)
	s.Error(err)
	s.arr.AssertExpectations(s.T())
	s.rcf.AssertExpectations(s.T())
	s.rrc.AssertExpectations(s.T())
}

func (s *updateAccessPolicyTestSuite) getMockSelectedRepos() []*pbtypes.Identity {
	var repoGlobalIds = []types.GlobalID{"abc123", "abd123"}
	return types.IdentitiesFromGlobalIDs(repoGlobalIds)
}

func (s *updateAccessPolicyTestSuite) getMockAccessPolicy() *azp.AccessPolicy {
	var repoGlobalIds = []types.GlobalID{"abc123", "abd123"}
	return &azp.AccessPolicy{
		PermissionType:       "selectedRepos",
		SelectedRepositories: repoGlobalIds,
	}
}

func (s *updateAccessPolicyTestSuite) getMockExistingAccessPolicy() *azp.AccessPolicy {
	return &azp.AccessPolicy{
		PermissionType: "allRepos",
	}
}
