package deploy

import (
	"context"
	"testing"

	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"

	"github.com/github/launch/clients/ghtwirp"
	"github.com/github/launch/db/stores/deployer"
	"github.com/github/launch/observability"
	"github.com/github/launch/observability/logger"
	"github.com/github/launch/observability/statter"
	"github.com/github/launch/pkg/schedulemanager"
	"github.com/github/launch/services/deploy/adminevents"
	"github.com/github/launch/services/deploy/workflowcanceler"
	"github.com/github/launch/services/pbtypes/launchtypes"
	"github.com/github/launch/types"
)

func TestDeployer_NotifyRepository(t *testing.T) {
	tests := []struct {
		action           string
		reportAdminEvent bool
		IsEnterprise     bool
	}{
		{
			action: "unarchived",
		},
		{
			action: "edited",
		},
		{
			action:           "archived",
			reportAdminEvent: false,
			IsEnterprise:     false,
		},
		{
			action:           "archived",
			reportAdminEvent: true,
			IsEnterprise:     true,
		},
		{
			action:           "deleted",
			reportAdminEvent: false,
			IsEnterprise:     false,
		},
		{
			action:           "deleted",
			reportAdminEvent: true,
			IsEnterprise:     true,
		},
	}

	for _, test := range tests {
		event := &launchtypes.NotifyRepositoryEvent{
			Action:                test.action,
			RepositoryNodeId:      types.IdentityFromGlobalID(testRepoID),
			RepositoryOwnerNodeId: types.IdentityFromGlobalID(testRepoOwnerID),
		}

		scheduleMngr := &schedulemanager.MockManager{}
		scheduleMngr.On("NotifyRepository", mock.Anything, event).Return(nil, nil).Once()

		canceler := &workflowcanceler.MockCanceler{}
		twp := &ghtwirp.MockClient{}
		rpt := &adminevents.MockReporter{}
		wbr := &deployer.MockWorkflowBuildsRepository{}
		twp.On("GetNextGlobalID", mock.Anything, mock.Anything).Return(
			func(ctx context.Context, globalID string) types.GlobalID {
				return types.GlobalID(globalID)
			}, nil)

		if test.reportAdminEvent {
			var action string
			if test.action == "archived" {
				action = adminevents.RepositoryArchived
			} else if test.action == "deleted" {
				action = adminevents.RepositoryDeleted
			}
			testRepoResID := testRepoID
			testRepoOwnerResID := testRepoOwnerID
			testRepoResID = testRepoID
			testRepoOwnerResID = testRepoOwnerID

			rpt.On("ReportRepoAdminEvent", mock.Anything, testRepoResID, action, map[string]string{"repo_global_id": testRepoResID.String(), "repo_owner_global_id": testRepoOwnerResID.String()}).Return(nil).Once()
		}

		log := logger.TestLogger()
		obs := observability.NewTestObservability()
		nullStatter := statter.NullStatter()
		svc := makeService(config{
			Log:                 log,
			Obs:                 obs,
			Stats:               nullStatter,
			ScheduleManager:     scheduleMngr,
			WorkflowBuilds:      wbr,
			WorkflowCanceler:    canceler,
			GithubTwirpClient:   twp,
			AdminEventsReporter: rpt,
		})
		svc.IsEnterprise = test.IsEnterprise
		migrator := deployer.NewGlobalIDMigrator(twp)
		svc.gidMigrator = migrator

		ctx := context.Background()

		_, err := svc.NotifyRepository(ctx, event)

		require.NoError(t, err)
		scheduleMngr.AssertExpectations(t)
		canceler.AssertExpectations(t)
		twp.AssertExpectations(t)
		rpt.AssertExpectations(t)
		wbr.AssertExpectations(t)
	}
}
