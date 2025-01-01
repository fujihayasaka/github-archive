package runnergroups

import (
	context "context"
	"testing"

	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/suite"

	db "github.com/github/launch/db/stores/deployer"
	"github.com/github/launch/observability/logger"
	"github.com/github/launch/observability/statter"
	"github.com/github/launch/pkg/azp"
	pbtypes "github.com/github/launch/services/pbtypes"
	"github.com/github/launch/types"
	"github.com/github/launch/workflowbuild/azp/azptypes"
)

type updateGroupTestSuite struct {
	suite.Suite

	svc *service

	rcf *azp.MockRepositoryClientFactory
	arr *db.MockAzpResourcesRepository
	rrc *azp.MockRepositoryClient
}

func TestUpdateGroupTestSuite(t *testing.T) {
	suite.Run(t, new(updateGroupTestSuite))
}

func (s *updateGroupTestSuite) SetupTest() {
	s.rcf = &azp.MockRepositoryClientFactory{}
	s.arr = &db.MockAzpResourcesRepository{}
	s.rrc = &azp.MockRepositoryClient{}
	s.svc = &service{
		log:                  logger.TestLogger(),
		stats:                statter.NullStatter(),
		azpRepoClientFactory: s.rcf,
		azpResourceRepo:      s.arr,
	}
}

func (s *updateGroupTestSuite) TestServiceWillBulkUpdateRunnerIds() {
	runnerGroup := mockRunnerGroup()
	runnerGroup.OwningTenant = types.NilGlobalID

	// The ^ runnerGroup has no runners assigned. So we expect the operation we construct to add everything from the Request.
	expectedRunnerOps := []azp.RunnerOp{
		{
			Op:    "add",
			Path:  "/runners",
			Value: []int64{1, 2, 3, 4},
		},
	}

	s.arr.On("TryGet", mock.Anything, mock.Anything).Return(&azptypes.BackingResources{}, nil)
	s.rcf.On("ClientFromResources", mock.Anything, mock.Anything).Return(s.rrc)
	s.rrc.On("UpdateVisibility", mock.Anything, mock.Anything, "ALL", mock.Anything, azp.AllowPublicUnknown, mock.Anything, azp.RestrictedToWorkflowsUnknown).Return(nil)
	s.rrc.On("GetGroup", mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(runnerGroup, nil)
	s.rrc.On("UpdateGroup", mock.Anything, mock.Anything, mock.Anything, expectedRunnerOps, mock.Anything, mock.Anything).Return(runnerGroup, nil)

	req := &UpdateGroupRequest{
		OwnerId: &pbtypes.Identity{
			GlobalId: "GlobalId",
		},
		PlanOwnerId: &pbtypes.Identity{
			GlobalId: "PlanOwnerGlobalId",
		},
		Name:             runnerGroup.Name,
		UpdateVisibility: UpdateVisibility_UPDATE_ALL,
		RunnerIds:        []int64{1, 2, 3, 4},
	}

	res, err := s.svc.UpdateGroup(context.Background(), req)
	s.NotNil(res)
	s.NoError(err)
	s.arr.AssertExpectations(s.T())
	s.rcf.AssertExpectations(s.T())
	s.rrc.AssertExpectations(s.T())
	s.Equal(res.RunnerGroup.GetId(), runnerGroup.ID)
	s.Equal(res.RunnerGroup.GetName(), runnerGroup.Name)
	s.Equal(res.RunnerGroup.GetVisibility(), Visibility_ALL)
	s.Equal(res.RunnerGroup.GetWorkflowRestrictionsReadOnly(), false)
}

func (s *updateGroupTestSuite) TestServiceWillRemoveRunnerIds() {
	runnerGroup := mockRunnerGroup()
	runnerGroup.OwningTenant = types.NilGlobalID

	existingRunner := &azp.RunnerV2{
		ID: 1,
	}
	existingRunner2 := &azp.RunnerV2{
		ID: 5,
	}
	runnerGroup.Runners = []*azp.RunnerV2{existingRunner, existingRunner2}

	// The ^ runnerGroup has two runners assigned. So we expect to have both Add and Remove operations based on what is in the UpdateGroupRequest
	expectedRunnerOps := []azp.RunnerOp{
		{
			Op:    "add",
			Path:  "/runners",
			Value: []int64{2, 3, 4}, // We don't add runner 1 because it already exists.
		},
		{
			Op:    "remove",
			Path:  "/runners",
			Value: []int64{5}, // We remove runner 5 because it's not in the bulk update payload
		},
	}

	s.arr.On("TryGet", mock.Anything, mock.Anything).Return(&azptypes.BackingResources{}, nil)
	s.rcf.On("ClientFromResources", mock.Anything, mock.Anything).Return(s.rrc)
	s.rrc.On("UpdateVisibility", mock.Anything, mock.Anything, "ALL", mock.Anything, azp.AllowPublicUnknown, mock.Anything, azp.RestrictedToWorkflowsUnknown).Return(nil)
	s.rrc.On("GetGroup", mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(runnerGroup, nil)
	s.rrc.On("UpdateGroup", mock.Anything, mock.Anything, runnerGroup.ID, expectedRunnerOps, runnerGroup.Name).Return(runnerGroup, nil)

	req := &UpdateGroupRequest{
		OwnerId: &pbtypes.Identity{
			GlobalId: "GlobalId",
		},
		PlanOwnerId: &pbtypes.Identity{
			GlobalId: "PlanOwnerGlobalId",
		},
		GroupId:          runnerGroup.ID,
		Name:             runnerGroup.Name,
		UpdateVisibility: UpdateVisibility_UPDATE_ALL,
		RunnerIds:        []int64{1, 2, 3, 4},
	}

	res, err := s.svc.UpdateGroup(context.Background(), req)
	s.NotNil(res)
	s.NoError(err)
	s.arr.AssertExpectations(s.T())
	s.rcf.AssertExpectations(s.T())
	s.rrc.AssertExpectations(s.T())
	s.Equal(res.RunnerGroup.GetId(), runnerGroup.ID)
	s.Equal(res.RunnerGroup.GetName(), runnerGroup.Name)
	s.Equal(res.RunnerGroup.GetWorkflowRestrictionsReadOnly(), false)
}

func (s *updateGroupTestSuite) TestServiceWillSkipUpdatesForInheritedGroups() {
	runnerGroup := mockRunnerGroup() // OwningTenant is non-empty, so this is an inherited group
	runnerGroup.Visibility.VisibilityType = "selected"

	s.arr.On("TryGet", mock.Anything, mock.Anything).Return(&azptypes.BackingResources{}, nil)
	s.rcf.On("ClientFromResources", mock.Anything, mock.Anything).Return(s.rrc)
	s.rrc.On("UpdateVisibility", mock.Anything, mock.Anything, "SELECTED", mock.Anything, azp.AllowPublicUnknown, mock.Anything, azp.RestrictedToWorkflowsUnknown).Return(nil)
	s.rrc.On("GetGroup", mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(runnerGroup, nil)

	req := &UpdateGroupRequest{
		OwnerId: &pbtypes.Identity{
			GlobalId: "GlobalId",
		},
		PlanOwnerId: &pbtypes.Identity{
			GlobalId: "PlanOwnerGlobalId",
		},
		GroupId:          runnerGroup.ID,
		Name:             runnerGroup.Name,
		UpdateVisibility: UpdateVisibility_UPDATE_SELECTED,
		RunnerIds:        []int64{1, 2, 3, 4},
	}

	res, err := s.svc.UpdateGroup(context.Background(), req)
	s.NotNil(res)
	s.NoError(err)
	s.arr.AssertExpectations(s.T())
	s.rcf.AssertExpectations(s.T())
	s.rrc.AssertExpectations(s.T())
	s.Equal(res.RunnerGroup.GetId(), runnerGroup.ID)
	s.Equal(res.RunnerGroup.GetName(), runnerGroup.Name)
	s.Equal(res.RunnerGroup.GetWorkflowRestrictionsReadOnly(), false)
	s.Equal(res.RunnerGroup.GetVisibility(), Visibility_SELECTED)
}

func (s *updateGroupTestSuite) TestServiceWillUseUpdatedVisibilityEnum() {
	runnerGroup := mockRunnerGroup()
	runnerGroup.OwningTenant = types.NilGlobalID
	runnerGroup.Visibility = azp.Visibility{
		VisibilityType: "selected",
	}

	s.arr.On("TryGet", mock.Anything, mock.Anything).Return(&azptypes.BackingResources{}, nil)
	s.rcf.On("ClientFromResources", mock.Anything, mock.Anything).Return(s.rrc)
	s.rrc.On("UpdateVisibility", mock.Anything, mock.Anything, "SELECTED", mock.Anything, azp.AllowPublicUnknown, mock.Anything, azp.RestrictedToWorkflowsUnknown).Return(nil)
	s.rrc.On("GetGroup", mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(runnerGroup, nil)
	s.rrc.On("UpdateGroup", mock.Anything, mock.Anything, runnerGroup.ID, []azp.RunnerOp(nil), runnerGroup.Name).Return(runnerGroup, nil)

	req := &UpdateGroupRequest{
		OwnerId: &pbtypes.Identity{
			GlobalId: "GlobalId",
		},
		PlanOwnerId: &pbtypes.Identity{
			GlobalId: "PlanOwnerGlobalId",
		},
		GroupId: runnerGroup.ID,
		Name:    runnerGroup.Name,

		UpdateVisibility: UpdateVisibility_UPDATE_SELECTED,
	}

	res, err := s.svc.UpdateGroup(context.Background(), req)
	s.NotNil(res)
	s.NoError(err)
	s.arr.AssertExpectations(s.T())
	s.rcf.AssertExpectations(s.T())
	s.rrc.AssertExpectations(s.T())
	s.Equal(res.RunnerGroup.GetId(), runnerGroup.ID)
	s.Equal(res.RunnerGroup.GetName(), runnerGroup.Name)
	s.Equal(res.RunnerGroup.GetVisibility(), Visibility_SELECTED)
	s.Equal(res.RunnerGroup.GetWorkflowRestrictionsReadOnly(), false)
}

func (s *updateGroupTestSuite) TestServiceWillUseAllowPublicEnum() {
	runnerGroup := mockRunnerGroup()
	runnerGroup.OwningTenant = types.NilGlobalID
	runnerGroup.Visibility = azp.Visibility{
		VisibilityType: "selected",
		AllowPublic:    true,
	}

	s.arr.On("TryGet", mock.Anything, mock.Anything).Return(&azptypes.BackingResources{}, nil)
	s.rcf.On("ClientFromResources", mock.Anything, mock.Anything).Return(s.rrc)
	s.rrc.On("UpdateVisibility", mock.Anything, mock.Anything, "SELECTED", mock.Anything, azp.AllowPublicAllow, mock.Anything, azp.RestrictedToWorkflowsUnknown).Return(nil)
	s.rrc.On("GetGroup", mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(runnerGroup, nil)
	s.rrc.On("UpdateGroup", mock.Anything, mock.Anything, runnerGroup.ID, []azp.RunnerOp(nil), runnerGroup.Name).Return(runnerGroup, nil)

	req := &UpdateGroupRequest{
		OwnerId: &pbtypes.Identity{
			GlobalId: "GlobalId",
		},
		PlanOwnerId: &pbtypes.Identity{
			GlobalId: "PlanOwnerGlobalId",
		},
		GroupId: runnerGroup.ID,
		Name:    runnerGroup.Name,

		UpdateVisibility: UpdateVisibility_UPDATE_SELECTED,
		AllowPublic:      UpdateAllowPublic_ALLOW_PUBLIC_ALLOW,
	}

	res, err := s.svc.UpdateGroup(context.Background(), req)
	s.NotNil(res)
	s.NoError(err)
	s.arr.AssertExpectations(s.T())
	s.rcf.AssertExpectations(s.T())
	s.rrc.AssertExpectations(s.T())
	s.Equal(res.RunnerGroup.GetId(), runnerGroup.ID)
	s.Equal(res.RunnerGroup.GetName(), runnerGroup.Name)
	s.Equal(res.RunnerGroup.GetVisibility(), Visibility_SELECTED)
	s.Equal(res.RunnerGroup.GetAllowPublic(), true)
	s.Equal(res.RunnerGroup.GetWorkflowRestrictionsReadOnly(), false)
}

func (s *updateGroupTestSuite) TestServiceWillUseRestrictedToWorkflowsEnum() {
	runnerGroup := mockRunnerGroup()
	runnerGroup.OwningTenant = types.NilGlobalID
	runnerGroup.Visibility = azp.Visibility{
		VisibilityType:        "selected",
		AllowPublic:           true,
		RestrictedToWorkflows: true,
	}

	s.arr.On("TryGet", mock.Anything, mock.Anything).Return(&azptypes.BackingResources{}, nil)
	s.rcf.On("ClientFromResources", mock.Anything, mock.Anything).Return(s.rrc)
	s.rrc.On("UpdateVisibility", mock.Anything, mock.Anything, "SELECTED", mock.Anything, azp.AllowPublicAllow, mock.Anything, azp.RestrictedToWorkflowsRestricted).Return(nil)
	s.rrc.On("GetGroup", mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(runnerGroup, nil)
	s.rrc.On("UpdateGroup", mock.Anything, mock.Anything, runnerGroup.ID, []azp.RunnerOp(nil), runnerGroup.Name).Return(runnerGroup, nil)

	req := &UpdateGroupRequest{
		OwnerId: &pbtypes.Identity{
			GlobalId: "GlobalId",
		},
		PlanOwnerId: &pbtypes.Identity{
			GlobalId: "PlanOwnerGlobalId",
		},
		GroupId: runnerGroup.ID,
		Name:    runnerGroup.Name,

		UpdateVisibility:      UpdateVisibility_UPDATE_SELECTED,
		AllowPublic:           UpdateAllowPublic_ALLOW_PUBLIC_ALLOW,
		RestrictedToWorkflows: UpdateRestrictedToWorkflows_RESTRICTED_TO_WORKFLOWS_RESTRICTED,
	}

	res, err := s.svc.UpdateGroup(context.Background(), req)
	s.NotNil(res)
	s.NoError(err)
	s.arr.AssertExpectations(s.T())
	s.rcf.AssertExpectations(s.T())
	s.rrc.AssertExpectations(s.T())
	s.Equal(res.RunnerGroup.GetId(), runnerGroup.ID)
	s.Equal(res.RunnerGroup.GetName(), runnerGroup.Name)
	s.Equal(res.RunnerGroup.GetVisibility(), Visibility_SELECTED)
	s.Equal(res.RunnerGroup.GetAllowPublic(), true)
	s.Equal(res.RunnerGroup.GetRestrictedToWorkflows(), true)
	s.Equal(res.RunnerGroup.GetWorkflowRestrictionsReadOnly(), false)
}

func (s *updateGroupTestSuite) TestServiceWillRespectWorkflowRestrictionsReadOnly() {
	runnerGroup := mockRunnerGroup()
	runnerGroup.OwningTenant = types.NilGlobalID
	runnerGroup.Visibility = azp.Visibility{
		VisibilityType:               "selected",
		AllowPublic:                  true,
		RestrictedToWorkflows:        true,
		WorkflowRestrictionsReadOnly: true,
	}

	s.arr.On("TryGet", mock.Anything, mock.Anything).Return(&azptypes.BackingResources{}, nil)
	s.rcf.On("ClientFromResources", mock.Anything, mock.Anything).Return(s.rrc)
	s.rrc.On("UpdateVisibility", mock.Anything, mock.Anything, "SELECTED", mock.Anything, azp.AllowPublicAllow, mock.Anything, azp.RestrictedToWorkflowsUnknown).Return(nil)
	s.rrc.On("GetGroup", mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(runnerGroup, nil)
	s.rrc.On("UpdateGroup", mock.Anything, mock.Anything, runnerGroup.ID, []azp.RunnerOp(nil), runnerGroup.Name).Return(runnerGroup, nil)

	req := &UpdateGroupRequest{
		OwnerId: &pbtypes.Identity{
			GlobalId: "GlobalId",
		},
		PlanOwnerId: &pbtypes.Identity{
			GlobalId: "PlanOwnerGlobalId",
		},
		GroupId: runnerGroup.ID,
		Name:    runnerGroup.Name,

		UpdateVisibility:      UpdateVisibility_UPDATE_SELECTED,
		AllowPublic:           UpdateAllowPublic_ALLOW_PUBLIC_ALLOW,
		RestrictedToWorkflows: UpdateRestrictedToWorkflows_RESTRICTED_TO_WORKFLOWS_RESTRICTED,
	}

	res, err := s.svc.UpdateGroup(context.Background(), req)
	s.NotNil(res)
	s.NoError(err)
	s.arr.AssertExpectations(s.T())
	s.rcf.AssertExpectations(s.T())
	s.rrc.AssertExpectations(s.T())
	s.Equal(res.RunnerGroup.GetWorkflowRestrictionsReadOnly(), true)
}

func (s *updateGroupTestSuite) TestServiceWillUseCorrectVisibility() {
	runnerGroup := mockRunnerGroup()
	runnerGroup.OwningTenant = types.NilGlobalID

	runnerGroup.Visibility = azp.Visibility{
		VisibilityType:               "selected",
		AllowPublic:                  true,
		RestrictedToWorkflows:        true,
		WorkflowRestrictionsReadOnly: false,
	}

	s.arr.On("TryGet", mock.Anything, mock.Anything).Return(&azptypes.BackingResources{}, nil)
	s.rcf.On("ClientFromResources", mock.Anything, mock.Anything).Return(s.rrc)
	s.rrc.On("UpdateVisibility", mock.Anything, mock.Anything, "SELECTED", mock.Anything, azp.AllowPublicAllow, mock.Anything, azp.RestrictedToWorkflowsRestricted).Return(nil)
	s.rrc.On("GetGroup", mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(runnerGroup, nil)
	s.rrc.On("UpdateGroup", mock.Anything, mock.Anything, runnerGroup.ID, []azp.RunnerOp(nil), runnerGroup.Name).Return(runnerGroup, nil)

	req := &UpdateGroupRequest{
		OwnerId: &pbtypes.Identity{
			GlobalId: "GlobalId",
		},
		PlanOwnerId: &pbtypes.Identity{
			GlobalId: "PlanOwnerGlobalId",
		},
		GroupId: runnerGroup.ID,
		Name:    runnerGroup.Name,

		UpdateVisibility:      UpdateVisibility_UPDATE_SELECTED,
		AllowPublic:           UpdateAllowPublic_ALLOW_PUBLIC_ALLOW,
		RestrictedToWorkflows: UpdateRestrictedToWorkflows_RESTRICTED_TO_WORKFLOWS_RESTRICTED,
	}

	res, err := s.svc.UpdateGroup(context.Background(), req)
	s.NotNil(res)
	s.NoError(err)
	s.arr.AssertExpectations(s.T())
	s.rcf.AssertExpectations(s.T())
	s.rrc.AssertExpectations(s.T())
	s.Equal(res.RunnerGroup.GetRestrictedToWorkflows(), true)
	s.Equal(res.RunnerGroup.GetVisibility(), Visibility_SELECTED)
	s.Equal(res.RunnerGroup.GetWorkflowRestrictionsReadOnly(), false)
}
