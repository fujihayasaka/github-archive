package deployer

import (
	"context"
	"database/sql"
	"fmt"
	"os"
	"strings"
	"testing"
	"time"

	"github.com/facebookgo/clock"
	"github.com/google/uuid"
	"github.com/pkg/errors"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"
	"github.com/stretchr/testify/suite"

	"github.com/github/launch/pkg/mu/muhttp/mw"
	"github.com/github/launch/pkg/payloads"

	"github.com/github/launch/clients/ghtwirp"
	"github.com/github/launch/clients/github"
	"github.com/github/launch/clients/github/tokens"
	hydro_metadata "github.com/github/launch/clients/hydro/metadata"
	dbpayloads "github.com/github/launch/db/stores/payloads"
	"github.com/github/launch/mysqldb"
	"github.com/github/launch/observability"
	"github.com/github/launch/observability/statter"
	"github.com/github/launch/services/deploy/deliveryguid"
	"github.com/github/launch/types"
	"github.com/github/launch/utils/asql"
	"github.com/github/launch/utils/ghtenant"
	"github.com/github/launch/utils/requestid"
	"github.com/github/launch/utils/requiredworkflowutils"
	"github.com/github/launch/utils/testutils"
	"github.com/github/launch/workflowbuild/build"
)

const (
	nextIDPrefix = "next-"

	repositoryID      = types.GlobalID("repo-1")
	repositoryID2     = types.GlobalID("repo-2")
	commitSha         = types.CommitSha("commit-1")
	commitRef         = types.GitRef("ref/heads/master")
	checkoutSha       = types.CommitSha("commit-2")
	checkoutRef       = types.GitRef("ref/heads/branch")
	requestID         = requestid.RequestID("test-request-id-1")
	workflowFilePath  = ".github/test.workflow"
	triggerType       = "push"
	workflowRunID     = 1
	workflowRunNumber = 1
	actorID           = types.GlobalID("actor-id")
)

var exampleMD = &hydro_metadata.WorkflowMetadata{
	Actor: &hydro_metadata.WorkflowMetadataActor{
		Login:        "user-1",
		IsDependabot: false,
	},
}

type WorkflowBuildsRepositorySuite struct {
	suite.Suite
	conn, payloadsConn *sql.DB
	clock              *clock.Mock
	builds             WorkflowBuildsRepository
	buildsRO           WorkflowBuildsRepositoryReadOnly
	payloads           payloads.Store
	executions         WorkflowBuildExecutionsRepository
	globalIDMigrator   GlobalIDMigrator
	mockTwirpClient    *ghtwirp.MockClient
	obs                *observability.Observability
	adb                *asql.SQL
}

func (s *WorkflowBuildsRepositorySuite) SetupSuite() {
	payloadsConn, err := mysqldb.NewDB(statter.NullStatter(), os.Getenv("ACTIONS_PAYLOADS_TEST_DATABASE_URL"))
	s.Require().NoError(err)

	s.obs = observability.NewTestObservability()

	conn, err := mysqldb.NewDB(statter.NullStatter(), os.Getenv("LAUNCH_DEPLOYER_TEST_DATABASE_URL"))
	s.Require().NoError(err)
	s.conn = conn
	s.payloadsConn = payloadsConn
	s.clock = clock.NewMock()
	pdb := asql.New(payloadsConn, s.obs.Logger, s.obs.Statter, testutils.NewNoopBreaker(), asql.PayloadsCluster)
	s.payloads = dbpayloads.New(pdb, s.obs.Logger, s.obs.Statter)
	s.adb = asql.New(conn, s.obs.Logger, s.obs.Statter, testutils.NewNoopBreaker(), asql.LaunchCluster)
	s.mockTwirpClient = ghtwirp.NewMockClient(s.T())
	s.globalIDMigrator = NewGlobalIDMigrator(s.mockTwirpClient)
	s.executions = NewWorkflowBuildExecutionsRepository(s.adb, s.obs, s.clock, s.globalIDMigrator)
}

func (s *WorkflowBuildsRepositorySuite) SetupTest() {
	s.builds = NewWorkflowBuildsRepository(s.adb, s.obs.Logger, s.obs.Statter, s.clock, s.payloads, s.executions, s.globalIDMigrator, false)
	s.buildsRO = NewWorkflowBuildsRepositoryReadOnly(s.adb, s.obs.Logger, s.obs.Statter, s.clock, s.globalIDMigrator, false)
	s.mockTwirpClient.On("GetNextGlobalID", mock.Anything, mock.Anything).Return(func(ctx context.Context, globalID string) types.GlobalID {
		if strings.HasPrefix(globalID, nextIDPrefix) {
			// already a next id, return original argument
			return types.GlobalID(globalID)
		}
		return nextIDFromGlobalID(types.GlobalID(globalID))
	}, nil)

	// clean out DB
	_, err := s.conn.Exec(`TRUNCATE workflow_builds`)
	s.Require().NoError(err)
	_, err = s.conn.Exec(`TRUNCATE workflow_build_executions`)
	s.Require().NoError(err)
	_, err = s.payloadsConn.Exec(`TRUNCATE payloads`)
	s.Require().NoError(err)
}

func (s *WorkflowBuildsRepositorySuite) TearDownSuite() {
	err := s.conn.Close()
	s.Require().NoError(err)
	err = s.payloadsConn.Close()
	s.Require().NoError(err)
}

func (s *WorkflowBuildsRepositorySuite) TestPersist() {
	ctx := context.Background()
	s.persistedCheckRunBuild(ctx, 0)
}

func (s *WorkflowBuildsRepositorySuite) TestPersist_SetNextGlobalIdColumns() {
	build, workflowMetadata, checkRunSuite, _ := s.makeBuild()
	checkRunSuite.RepositoryID = types.GlobalID("repo-id")

	// Need to use a different mock for one of the GetNextGlobalID calls in TestSetup so we have to reset everything
	s.mockTwirpClient.ExpectedCalls = []*mock.Call{}
	s.mockTwirpClient.EXPECT().GetNextGlobalID(mock.Anything, checkRunSuite.RepositoryID.String()).Return(types.GlobalID(nextIDPrefix+checkRunSuite.RepositoryID), nil)
	s.mockTwirpClient.EXPECT().GetNextGlobalID(mock.Anything, "").Return(types.NilGlobalID, nil)
	s.mockTwirpClient.EXPECT().GetNextGlobalID(mock.Anything, checkRunSuite.CheckSuiteIDPair.GlobalID.String()).Return(types.GlobalID(nextIDPrefix+checkRunSuite.CheckSuiteIDPair.GlobalID), nil)

	ctx := context.WithValue(context.Background(), mw.RequestIDKey, string(requestID))
	buildID, _, _, _, err := s.builds.Persist(ctx, build, checkRunSuite.RepositoryID, checkRunSuite.EventSHA, checkRunSuite.EventRef, checkRunSuite.FlowIdentifier, workflowMetadata, &tokens.PermissionSettings{}, build.EventPayload, types.NilGlobalID, types.NilGlobalID, ghtenant.GitHubTenant{})
	s.NoError(err)

	rows := s.conn.QueryRow(`select repository_id, repository_next_id, check_suite_id, check_suite_next_id, executing_actor_id, executing_actor_next_id from workflow_builds where id = ?`, buildID)

	var repoIDRes, repoNextIDRes, csIDRes, csNextIDRes, execActorIDRes, execActorNextIDRes types.GlobalID
	s.Require().NoError(rows.Scan(&repoIDRes, &repoNextIDRes, &csIDRes, &csNextIDRes, &execActorIDRes, &execActorNextIDRes))

	s.Require().Equal(repoIDRes, repoNextIDRes)
	s.Require().Equal(csIDRes, csNextIDRes)
	s.Require().Equal(execActorIDRes, execActorNextIDRes)
}

func (s *WorkflowBuildsRepositorySuite) TestPersist_CreatesWorkflowBuildExecution() {
	ctx := context.Background()
	b, _, _ := s.persistedCheckRunBuild(ctx, 0)

	res, err := s.executions.GetByPlanIDForTests(ctx, b.ExecutionID)
	s.NoError(err)

	s.Equal(b.ExecutionID, res.PlanID)
	s.Equal(b.ExternalID, res.ExternalBuildID)
	s.Equal(nextIDFromGlobalID(actorID), res.TriggeringActorID)
	s.Equal(1, res.Attempt)
}

func (s *WorkflowBuildsRepositorySuite) TestPersist_AndLoadPermissions() {
	build, workflowMetadata, checkRunSuite, _ := s.makeBuild()
	checkRunSuite.RepositoryID = types.GlobalID("repo-id")
	perms := &tokens.PermissionSettings{
		InstallationPermissions: tokens.InstallationPermissions{
			Checks:       tokens.WriteAccess,
			Issues:       tokens.WriteAccess,
			PullRequests: tokens.ReadAccess,
		},
		DefaultPermissions: tokens.WritePermissions,
	}

	ctx := context.WithValue(context.Background(), mw.RequestIDKey, string(requestID))
	buildID, _, eventTime, persistedPayload, err := s.builds.Persist(ctx, build, checkRunSuite.RepositoryID, checkRunSuite.EventSHA, checkRunSuite.EventRef, checkRunSuite.FlowIdentifier, workflowMetadata, perms, build.EventPayload, types.NilGlobalID, types.NilGlobalID, ghtenant.GitHubTenant{})
	s.NoError(err)
	s.Assert().True(persistedPayload)
	s.Assert().False(eventTime.IsZero())

	err = s.builds.SetCheckSuiteInformation(ctx, buildID, checkRunSuite.CheckSuiteIDPair.GlobalID, checkRunSuite.WorkflowRunID, checkRunSuite.WorkflowRunNumber)
	s.NoError(err)

	loadedState, ok, err := s.builds.GetDataForTokenRequest(ctx, build.ExecutionID.String())
	s.NoError(err)
	s.True(ok)
	s.Equal(perms, loadedState.TokenPermissions)
}

func (s *WorkflowBuildsRepositorySuite) TestPersist_AndLoadPermissions_InfersDefaultWritePermissions() {
	build, workflowMetadata, checkRunSuite, _ := s.makeBuild()
	checkRunSuite.RepositoryID = types.GlobalID("repo-id")
	perms := &tokens.PermissionSettings{
		InstallationPermissions: *tokens.NewInstallationPermissions(tokens.WritePermissions),
	}

	ctx := context.WithValue(context.Background(), mw.RequestIDKey, string(requestID))
	buildID, _, eventTime, persistedPayload, err := s.builds.Persist(ctx, build, checkRunSuite.RepositoryID, checkRunSuite.EventSHA, checkRunSuite.EventRef, checkRunSuite.FlowIdentifier, workflowMetadata, perms, build.EventPayload, types.NilGlobalID, types.NilGlobalID, ghtenant.GitHubTenant{})
	s.NoError(err)
	s.Assert().True(persistedPayload)
	s.Assert().False(eventTime.IsZero())

	err = s.builds.SetCheckSuiteInformation(ctx, buildID, checkRunSuite.CheckSuiteIDPair.GlobalID, checkRunSuite.WorkflowRunID, checkRunSuite.WorkflowRunNumber)
	s.NoError(err)

	loadedState, ok, err := s.builds.GetDataForTokenRequest(ctx, build.ExecutionID.String())
	s.NoError(err)
	s.True(ok)
	perms.DefaultPermissions = tokens.WritePermissions
	s.Equal(perms, loadedState.TokenPermissions)
}

func (s *WorkflowBuildsRepositorySuite) TestPersist_MultiTenant() {

	type testCase struct {
		name          string
		ghTenantID    int64
		isMultiTenant bool
		shouldError   bool
	}

	testCases := []testCase{
		{
			name:       "non-multi-tenant/ignores-tenant-id",
			ghTenantID: int64(4),
		},
		{
			name:          "multi-tenant/valid-id",
			ghTenantID:    int64(4),
			isMultiTenant: true,
		},
		{
			name:          "multi-tenant/invalid-id",
			ghTenantID:    int64(0),
			isMultiTenant: true,
			shouldError:   true,
		},
	}

	for _, tc := range testCases {
		s.Run(tc.name, func() {

			s.builds = NewWorkflowBuildsRepository(s.adb, s.obs.Logger, s.obs.Statter, s.clock, s.payloads, s.executions, s.globalIDMigrator, tc.isMultiTenant)
			build, workflowMetadata, checkRunSuite, _ := s.makeBuild()

			checkRunSuite.RepositoryID = types.GlobalID("repo-id")
			perms := &tokens.PermissionSettings{
				InstallationPermissions: *tokens.NewInstallationPermissions(tokens.WritePermissions),
			}

			ctx := context.WithValue(context.Background(), mw.RequestIDKey, string(requestID))
			buildID, _, eventTime, persistedPayload, err := s.builds.Persist(ctx, build, checkRunSuite.RepositoryID, checkRunSuite.EventSHA, checkRunSuite.EventRef, checkRunSuite.FlowIdentifier, workflowMetadata, perms, build.EventPayload, types.NilGlobalID, types.NilGlobalID, ghtenant.GitHubTenant{ID: tc.ghTenantID, Slug: "test"})

			if tc.shouldError {
				s.Error(err)
				return
			}

			s.NoError(err)
			s.Assert().True(persistedPayload)
			s.Assert().False(eventTime.IsZero())

			rows := s.conn.QueryRow(`select github_tenant_id from workflow_builds where id = ?`, buildID)
			var actualTenantID sql.NullInt64
			s.Require().NoError(rows.Scan(&actualTenantID))

			if tc.isMultiTenant {
				s.True(actualTenantID.Valid)
				s.Equal(tc.ghTenantID, actualTenantID.Int64)
				return
			}

			s.False(actualTenantID.Valid)
			s.Equal(int64(0), actualTenantID.Int64)
		})
	}
}

func (s *WorkflowBuildsRepositorySuite) TestPersist_AndLoadPermissions_InfersDefaultReadPermissions() {
	build, workflowMetadata, checkRunSuite, _ := s.makeBuild()
	checkRunSuite.RepositoryID = types.GlobalID("repo-id")
	perms := &tokens.PermissionSettings{
		InstallationPermissions: *tokens.NewInstallationPermissions(tokens.ReadPermissions),
	}

	ctx := context.WithValue(context.Background(), mw.RequestIDKey, string(requestID))
	buildID, _, eventTime, persistedPayload, err := s.builds.Persist(ctx, build, checkRunSuite.RepositoryID, checkRunSuite.EventSHA, checkRunSuite.EventRef, checkRunSuite.FlowIdentifier, workflowMetadata, perms, build.EventPayload, types.NilGlobalID, types.NilGlobalID, ghtenant.GitHubTenant{})
	s.NoError(err)
	s.Assert().True(persistedPayload)
	s.Assert().False(eventTime.IsZero())

	err = s.builds.SetCheckSuiteInformation(ctx, buildID, checkRunSuite.CheckSuiteIDPair.GlobalID, checkRunSuite.WorkflowRunID, checkRunSuite.WorkflowRunNumber)
	s.NoError(err)

	loadedState, ok, err := s.builds.GetDataForTokenRequest(ctx, build.ExecutionID.String())
	s.NoError(err)
	s.True(ok)
	perms.DefaultPermissions = tokens.ReadPermissions
	s.Equal(perms, loadedState.TokenPermissions)
}

func (s *WorkflowBuildsRepositorySuite) TestPersist_PreviouslyPersisted() {
	build, workflowMetadata, checkRunSuite, _ := s.makeBuild()
	checkRunSuite.RepositoryID = types.GlobalID("repo-id")
	perms := &tokens.PermissionSettings{
		InstallationPermissions: tokens.InstallationPermissions{
			Checks:       tokens.WriteAccess,
			PullRequests: tokens.ReadAccess,
		},
	}

	ctx := context.WithValue(context.Background(), mw.RequestIDKey, string(requestID))
	buildID1, workflowExecutionID1, eventTime, persistedPayload, err := s.builds.Persist(
		ctx, build, checkRunSuite.RepositoryID, checkRunSuite.EventSHA, checkRunSuite.EventRef, checkRunSuite.FlowIdentifier, workflowMetadata, perms, build.EventPayload, types.NilGlobalID, types.NilGlobalID, ghtenant.GitHubTenant{})
	s.NoError(err)
	s.Assert().True(persistedPayload)
	s.Assert().False(eventTime.IsZero())

	// Act
	build.ExecutionID = types.NewRandomWorkflowExecutionID()
	buildID2, workflowExecutionID2, eventTime, persistedPayload, err := s.builds.Persist(
		ctx, build, checkRunSuite.RepositoryID, checkRunSuite.EventSHA, checkRunSuite.EventRef, checkRunSuite.FlowIdentifier, workflowMetadata, perms, build.EventPayload, types.NilGlobalID, types.NilGlobalID, ghtenant.GitHubTenant{})

	s.NoError(err)
	s.Assert().True(persistedPayload)
	s.Assert().False(eventTime.IsZero())
	s.Equal(buildID1, buildID2)
	s.Equal(workflowExecutionID1, workflowExecutionID2)
}

func (s *WorkflowBuildsRepositorySuite) TestPersist_NilPermissions_LoadsAsNil() {
	build, workflowMetadata, checkRunSuite, _ := s.makeBuild()
	checkRunSuite.RepositoryID = types.GlobalID("repo-id")
	ctx := context.WithValue(context.Background(), mw.RequestIDKey, string(requestID))
	buildID, _, eventTime, persistedPayload, err := s.builds.Persist(ctx, build, checkRunSuite.RepositoryID, checkRunSuite.EventSHA, checkRunSuite.EventRef, checkRunSuite.FlowIdentifier, workflowMetadata, nil, build.EventPayload, types.NilGlobalID, types.NilGlobalID, ghtenant.GitHubTenant{}) // Nil permissions
	s.NoError(err)
	s.Assert().True(persistedPayload)
	s.Assert().False(eventTime.IsZero())

	err = s.builds.SetCheckSuiteInformation(ctx, buildID, checkRunSuite.CheckSuiteIDPair.GlobalID, checkRunSuite.WorkflowRunID, checkRunSuite.WorkflowRunNumber)
	s.NoError(err)

	loadedState, ok, err := s.builds.GetDataForTokenRequest(ctx, build.ExecutionID.String())
	s.NoError(err)
	s.True(ok)
	s.Nil(loadedState.TokenPermissions)
}

func (s *WorkflowBuildsRepositorySuite) TestPersist_EventOriginTime() {
	build, workflowMetadata, checkRunSuite, _ := s.makeBuild()
	build.OriginTime = time.Now().UTC().Add(-1 * time.Hour)
	checkRunSuite.RepositoryID = types.GlobalID("repo-id")
	perms := &tokens.PermissionSettings{
		InstallationPermissions: tokens.InstallationPermissions{
			Checks:       tokens.WriteAccess,
			PullRequests: tokens.ReadAccess,
		},
	}

	ctx := context.WithValue(context.Background(), mw.RequestIDKey, string(requestID))
	_, _, eventTime, persistedPayload, err := s.builds.Persist(
		ctx, build, checkRunSuite.RepositoryID, checkRunSuite.EventSHA, checkRunSuite.EventRef, checkRunSuite.FlowIdentifier, workflowMetadata, perms, build.EventPayload, types.NilGlobalID, types.NilGlobalID, ghtenant.GitHubTenant{})
	s.NoError(err)
	s.Assert().True(persistedPayload)
	s.Assert().EqualValues(build.OriginTime, eventTime)
}

func (s *WorkflowBuildsRepositorySuite) TestPersist_RunServiceBackend() {
	ctx := context.Background()
	_, checkSuiteState, _ := s.persistedCheckRunBuild(ctx, 0, WithBackend(types.WorkflowBackendRunService))

	storedState, ok, err := s.builds.GetWorkflowBuildStateByCheckSuiteID(ctx, checkSuiteState.CheckSuiteIDPair.GlobalID)
	s.Require().NoError(err)
	s.True(ok)
	s.Assert().Equal(types.WorkflowBackendRunService, storedState.Backend)
}

func (s *WorkflowBuildsRepositorySuite) TestGetStateByCheckSuiteID() {
	ctx := context.Background()
	_, checkSuiteState, _ := s.persistedCheckRunBuild(ctx, 0, WithEventPayload([]byte("test")))

	storedState, ok, err := s.builds.GetStateByCheckSuiteID(ctx, checkSuiteState.CheckSuiteIDPair.GlobalID)
	s.Require().NoError(err)
	s.True(ok)
	s.Assert().Equal(checkSuiteState, storedState)
}

func (s *WorkflowBuildsRepositorySuite) TestGetStateByCheckSuiteID_RunServiceBackend() {
	ctx := context.Background()
	_, checkSuiteState, _ := s.persistedCheckRunBuild(ctx, 0, WithEventPayload([]byte("test")), WithBackend(types.WorkflowBackendRunService))

	storedState, ok, err := s.builds.GetStateByCheckSuiteID(ctx, checkSuiteState.CheckSuiteIDPair.GlobalID)
	s.Require().NoError(err)
	s.True(ok)
	s.Assert().Equal(checkSuiteState, storedState)
}

func (s *WorkflowBuildsRepositorySuite) Test_ResetWorkflowBuildState_WithCompleted() {
	ctx := context.Background()
	_, checkSuiteState, _ := s.persistedCheckRunBuild(ctx, 0)
	b, externalBuildID := s.makeMockBuild()

	// Complete the original job
	s.completeBuild(ctx, checkSuiteState)

	// Rerun the original job
	workflowBuildResetContext, err := s.builds.ResetWorkflowBuildState(ctx, checkSuiteState.CheckSuiteIDPair.GlobalID, b, &tokens.PermissionSettings{}, exampleMD, nextIDFromGlobalID(actorID), false)
	s.NoError(err)

	workflow, ok, err := s.builds.GetWorkflowBuildStateByCheckSuiteID(ctx, checkSuiteState.CheckSuiteIDPair.GlobalID)
	s.NoError(err)
	s.True(ok)
	s.NotNil(workflow)

	// Verify state after reset for rerun
	s.Equal(build.WorkflowStateNone, workflow.State)
	s.Nil(workflow.CompletedAt)
	s.Nil(workflow.QueuedAt)
	emptyUUID := uuid.UUID{}
	s.NotEqual(emptyUUID.String(), workflow.ExecutionID.String())
	s.Equal(externalBuildID, workflow.ExternalBuildID)
	s.Equal(workflow.ExecutionID, *workflowBuildResetContext.WorkflowExecutionID)
	s.Equal(int64(2), workflowBuildResetContext.Attempt)
	s.Equal(types.WorkflowBackendActionsService, workflowBuildResetContext.Backend)

	execution, err := s.executions.GetByPlanIDForTests(ctx, b.ExecutionID)
	s.NoError(err)
	s.NotNil(execution)
	s.Nil(execution.CompletedAt)
	s.Equal(build.WorkflowStateNone, execution.State)
	s.Equal(2, execution.Attempt)
	s.Equal(nextIDFromGlobalID(actorID), execution.TriggeringActorID)

	// Complete the rerun job
	s.completeBuild(ctx, checkSuiteState)

	workflow, ok, err = s.builds.GetWorkflowBuildStateByCheckSuiteID(ctx, checkSuiteState.CheckSuiteIDPair.GlobalID)
	s.NoError(err)
	s.True(ok)
	s.NotNil(workflow)

	// Verify that things have changed
	s.Equal(build.WorkflowStateFailed, workflow.State)
	s.NotNil(workflow.QueuedAt)

	execution, err = s.executions.GetByPlanIDForTests(ctx, b.ExecutionID)
	s.NoError(err)
	s.NotNil(execution)
	s.NotNil(execution.CompletedAt)
	s.Equal(build.WorkflowStateFailed, execution.State)
}

func (s *WorkflowBuildsRepositorySuite) Test_ResetWorkflowBuildState_AllowFourNinesReset() {
	ctx := context.Background()
	_, checkSuiteState, _ := s.persistedCheckRunBuild(ctx, 0)
	b, externalBuildID := s.makeMockBuild() // this is the "new" build that we will reset to
	b.Backend = types.WorkflowBackendRunService

	err := s.builds.TransitionToQueued(ctx, checkSuiteState.WorkflowBuildDatabaseID, externalBuildID)
	s.NoError(err)

	// We don't complete the original build, because in four nines architecture Launch never hears back about the run completion.

	// Reset the original build, but with allowFourNinesReset param = true
	workflowBuildResetContext, err := s.builds.ResetWorkflowBuildState(ctx, checkSuiteState.CheckSuiteIDPair.GlobalID, b, &tokens.PermissionSettings{}, exampleMD, nextIDFromGlobalID(actorID), true)
	s.NoError(err)

	workflow, ok, err := s.builds.GetWorkflowBuildStateByCheckSuiteID(ctx, checkSuiteState.CheckSuiteIDPair.GlobalID)
	s.NoError(err)
	s.True(ok)
	s.NotNil(workflow)

	// Verify state after reset for rerun
	s.Equal(types.WorkflowBackendRunService, workflow.Backend)
	s.Equal(build.WorkflowStateNone, workflow.State)
	s.Nil(workflow.QueuedAt)
	emptyUUID := uuid.UUID{}
	s.NotEqual(emptyUUID.String(), workflow.ExecutionID.String())
	s.Equal(externalBuildID, workflow.ExternalBuildID)
	s.Equal(workflow.ExecutionID, *workflowBuildResetContext.WorkflowExecutionID)
	s.Equal(int64(2), workflowBuildResetContext.Attempt)
	s.Equal(types.WorkflowBackendRunService, workflowBuildResetContext.Backend)

	execution, err := s.executions.GetByPlanIDForTests(ctx, b.ExecutionID)
	s.NoError(err)
	s.NotNil(execution)
	s.Nil(execution.CompletedAt)
	s.Equal(build.WorkflowStateNone, execution.State)
	s.Equal(2, execution.Attempt)
	s.Equal(nextIDFromGlobalID(actorID), execution.TriggeringActorID)
}

func (s *WorkflowBuildsRepositorySuite) Test_ResetWorkflowBuildState_SetsNextGlobalID() {
	ctx := context.Background()
	b, checkSuiteState, _ := s.persistedCheckRunBuild(ctx, 0)

	s.completeBuild(ctx, checkSuiteState)

	// Need to use a different mock for one of the GetNextGlobalID calls so we have to reset everything
	s.mockTwirpClient.ExpectedCalls = []*mock.Call{}
	s.mockTwirpClient.EXPECT().GetNextGlobalID(mock.Anything, checkSuiteState.CheckSuiteIDPair.GlobalID.String()).Return(types.GlobalID(checkSuiteState.CheckSuiteIDPair.GlobalID), nil)
	s.mockTwirpClient.EXPECT().GetNextGlobalID(mock.Anything, mock.Anything).Return(nextIDFromGlobalID(actorID), nil)

	// We need a new ExecutionID and WebhookDeliveryID for the workflow_build_execution that is written
	b.ExecutionID = types.NewRandomWorkflowExecutionID()
	b.WebhookDeliveryID = newWebhookDeliveryID()
	_, err := s.builds.ResetWorkflowBuildState(ctx, checkSuiteState.CheckSuiteIDPair.GlobalID, b, &tokens.PermissionSettings{}, exampleMD, nextIDFromGlobalID(actorID), false)
	s.Require().NoError(err)

	rows := s.conn.QueryRow(`select executing_actor_id, executing_actor_next_id from workflow_builds where id = ?`, checkSuiteState.WorkflowBuildDatabaseID)

	var execActorIDRes, execActorNextIDRes types.GlobalID
	s.Require().NoError(rows.Scan(&execActorIDRes, &execActorNextIDRes))
	s.Require().Equal(execActorIDRes, execActorNextIDRes)
}

func (s *WorkflowBuildsRepositorySuite) Test_ResetWorkflowBuildState_WithUpdatedPermissions() {
	ctx := context.Background()
	b, checkSuiteState, _ := s.persistedCheckRunBuild(ctx, 0)

	originalTokenData, _, _ := s.builds.GetDataForTokenRequest(ctx, b.ExecutionID.String())
	s.Assert().Equal("", string(originalTokenData.TokenPermissions.Contents))

	s.completeBuild(ctx, checkSuiteState)

	// We need a new ExecutionID and WebhookDeliveryID for the workflow_build_execution that is written
	b.ExecutionID = types.NewRandomWorkflowExecutionID()
	b.WebhookDeliveryID = newWebhookDeliveryID()
	_, err := s.builds.ResetWorkflowBuildState(ctx, checkSuiteState.CheckSuiteIDPair.GlobalID, b, &tokens.PermissionSettings{InstallationPermissions: *tokens.NewInstallationPermissions(tokens.ReadPermissions)}, exampleMD, types.NilGlobalID, false)
	s.Require().NoError(err)

	tokenData, _, _ := s.builds.GetDataForTokenRequest(ctx, b.ExecutionID.String())
	s.Assert().Equal(tokenData.TokenPermissions.Contents, tokens.ReadAccess)
	s.Assert().NotEqual(originalTokenData.TokenPermissions.Contents, tokenData.TokenPermissions.Contents)
}

func (s *WorkflowBuildsRepositorySuite) Test_ResetWorkflowBuildState_UpdatesReportingMetadataCorrectly() {
	ctx := context.Background()
	b, css, _ := s.persistedCheckRunBuild(ctx, 0)

	data, _, err := s.builds.GetDataForStatusPostback(ctx, b.ExecutionID.String())
	s.Require().NoError(err)
	s.Nil(data.WorkflowMetadata.Actor) // No actor is set originally

	s.completeBuild(ctx, css) // Mark complete

	// We need a new ExecutionID and WebhookDeliveryID for the workflow_build_execution that is written
	b.ExecutionID = types.NewRandomWorkflowExecutionID()
	b.WebhookDeliveryID = newWebhookDeliveryID()

	_, err = s.builds.ResetWorkflowBuildState(ctx, css.CheckSuiteIDPair.GlobalID, b, &tokens.PermissionSettings{InstallationPermissions: *tokens.NewInstallationPermissions(tokens.ReadPermissions)}, exampleMD, types.NilGlobalID, false)
	s.Require().NoError(err)

	data, _, err = s.builds.GetDataForStatusPostback(ctx, b.ExecutionID.String())
	s.Require().NoError(err)
	s.Equal(exampleMD.Actor, data.WorkflowMetadata.Actor)

	otherActorMD := &hydro_metadata.WorkflowMetadata{
		Actor: &hydro_metadata.WorkflowMetadataActor{
			Login:        "dependabot",
			IsDependabot: true, // Lets also test the true boolean value here.
		},
	}

	s.completeBuild(ctx, css) // Mark complete

	// We need a new ExecutionID and WebhookDeliveryID for the workflow_build_execution that is written
	b.ExecutionID = types.NewRandomWorkflowExecutionID()
	b.WebhookDeliveryID = newWebhookDeliveryID()

	_, err = s.builds.ResetWorkflowBuildState(ctx, css.CheckSuiteIDPair.GlobalID, b, &tokens.PermissionSettings{InstallationPermissions: *tokens.NewInstallationPermissions(tokens.ReadPermissions)}, otherActorMD, types.NilGlobalID, false)
	s.Require().NoError(err)

	data, _, err = s.builds.GetDataForStatusPostback(ctx, b.ExecutionID.String())
	s.Require().NoError(err)
	s.Equal(otherActorMD.Actor, data.WorkflowMetadata.Actor)

}

func (s *WorkflowBuildsRepositorySuite) TestResetWorkflowBuildStateNotCompleted() {
	ctx := context.Background()
	_, checkSuiteState, _ := s.persistedCheckRunBuild(ctx, 0)
	b, _ := s.makeMockBuild()

	_, err := s.builds.ResetWorkflowBuildState(ctx, checkSuiteState.CheckSuiteIDPair.GlobalID, b, &tokens.PermissionSettings{InstallationPermissions: *tokens.NewInstallationPermissions(tokens.ReadPermissions)}, exampleMD, types.NilGlobalID, false)
	s.Assert().Error(err)
}

func (s *WorkflowBuildsRepositorySuite) TestResetWorkflowBuildState_AlreadyResetReturnsExecutionID() {
	ctx := context.Background()
	_, checkSuiteState, _ := s.persistedCheckRunBuild(ctx, 0)
	b, _ := s.makeMockBuild()
	s.completeBuild(ctx, checkSuiteState)

	// Reset the completed, succeeded build
	_, err := s.builds.ResetWorkflowBuildState(
		ctx,
		checkSuiteState.CheckSuiteIDPair.GlobalID,
		b,
		&tokens.PermissionSettings{
			InstallationPermissions: *tokens.NewInstallationPermissions(tokens.ReadPermissions),
		},
		exampleMD,
		types.NilGlobalID,
		false,
	)
	s.NoError(err)
	workflowExecutionID := b.ExecutionID

	b.ExecutionID = types.NewRandomWorkflowExecutionID()

	// Reset a second time, with next check suite column
	res, err := s.builds.ResetWorkflowBuildState(
		ctx,
		checkSuiteState.CheckSuiteIDPair.GlobalID,
		b,
		&tokens.PermissionSettings{
			InstallationPermissions: *tokens.NewInstallationPermissions(tokens.ReadPermissions),
		},
		exampleMD,
		types.NilGlobalID,
		false,
	)

	// Lets confirm that we have the same ID in both builds.uuid and workflow_build_executions.plan_id in the end
	rows := s.conn.QueryRow(`SELECT b.uuid, x.plan_id
		FROM workflow_builds b
		JOIN workflow_build_executions x ON b.id=x.workflow_build_id
		WHERE x.webhook_delivery_id = ?`, b.WebhookDeliveryID)

	var bID, xID types.WorkflowExecutionID
	s.NoError(rows.Scan(&bID, &xID))
	s.Equal(bID.String(), xID.String())

	s.NoError(err)
	s.Equal(workflowExecutionID, *res.WorkflowExecutionID)
	s.Equal(int64(3), res.Attempt)
}

func (s *WorkflowBuildsRepositorySuite) TestResetWorkflowWithNoAssociatedExecution() {
	ctx := context.Background()
	_, checkSuiteState, _ := s.persistedCheckRunBuild(ctx, 0)
	b, _ := s.makeMockBuild()

	// Complete the original job
	s.completeBuild(ctx, checkSuiteState)

	// Fake a null execution
	_, err := s.conn.Exec(`DELETE FROM workflow_build_executions`)
	if err != nil {
		s.Fail("Unable to delete records from workflow_build_executions")
	}

	// Rerun the original job
	_, err = s.builds.ResetWorkflowBuildState(ctx, checkSuiteState.CheckSuiteIDPair.GlobalID, b, &tokens.PermissionSettings{}, exampleMD, nextIDFromGlobalID(actorID), false)
	s.NoError(err)

	execution, err := s.executions.GetByPlanIDForTests(ctx, b.ExecutionID)
	s.NoError(err)
	s.NotNil(execution)
	s.Equal(1, execution.Attempt)
}

func (s *WorkflowBuildsRepositorySuite) TestComplete_CreatesWorkflowBuildExecution() {
	ctx := context.Background()
	b, c, _ := s.persistedCheckRunBuild(ctx, 0)

	err := s.builds.Complete(ctx, time.Now(), time.Now(), c.WorkflowBuildDatabaseID, build.WorkflowStateSucceeded)
	s.Require().NoError(err)

	res, err := s.executions.GetByPlanIDForTests(ctx, b.ExecutionID)
	s.NoError(err)

	s.Equal(build.WorkflowStateSucceeded, res.State)
	s.NotNil(res.CompletedAt)
}

func (s *WorkflowBuildsRepositorySuite) TestGetStateByCheckRunID_ExcludeActions() {
	ctx := context.Background()
	_, checkSuiteState, _ := s.persistedCheckRunBuild(ctx, 0, WithEventPayload([]byte("test")))

	_, _, err := s.builds.GetStateByCheckSuiteID(ctx, checkSuiteState.CheckSuiteIDPair.GlobalID)
	s.Require().NoError(err)
}

func (s *WorkflowBuildsRepositorySuite) Test_GetWorkflowState_Success() {
	ctx := context.Background()

	wfb, css, _ := s.persistedCheckRunBuild(ctx, 0, WithPath(".github/workflows/test.yml"))
	err := s.builds.TransitionToQueued(ctx, css.WorkflowBuildDatabaseID, "azp-id")
	s.Require().NoError(err)

	state, ok, err := s.builds.GetWorkflowState(ctx, *wfb.WebhookDeliveryID, wfb.Event, wfb.FileReference)

	s.Require().NoError(err)
	s.True(ok)
	s.Require().NotNil(state)
	s.Assert().Equal(build.WorkflowStateQueued, *state)
}

func (s *WorkflowBuildsRepositorySuite) Test_GetWorkflowState_NotFound() {
	ctx := context.Background()

	badWorkflowFileReference := types.WorkflowFileReference{
		Path: "does not exist",
		Ref:  "refs/heads/main",
		SHA:  "da39a3ee5e6b4b0d3255bfef95601890afd80709",
	}

	state, ok, err := s.builds.GetWorkflowState(ctx, "some-id", "push", badWorkflowFileReference)

	s.Require().NoError(err)
	s.False(ok)
	s.Nil(state)
}

func (s *WorkflowBuildsRepositorySuite) Test_GetWorkflowRerunState_Success() {
	ctx := context.Background()

	wfb, css, _ := s.persistedCheckRunBuild(ctx, 0)
	err := s.builds.TransitionToQueued(ctx, css.WorkflowBuildDatabaseID, "azp-id")
	s.Require().NoError(err)

	state, ok, err := s.builds.GetWorkflowRerunState(ctx, *wfb.WebhookDeliveryID, wfb.Event, *wfb.WebhookDeliveryID, wfb.FileReference)

	s.Require().NoError(err)
	s.True(ok)
	s.Require().NotNil(state)
	s.Assert().Equal(build.WorkflowStateQueued, *state)
}

func (s *WorkflowBuildsRepositorySuite) Test_GetWorkflowRerunState_ExecutionNotFound() {
	ctx := context.Background()

	wfb, _, _ := s.persistedCheckRunBuild(ctx, 0)

	_, err := s.conn.Exec(`DELETE FROM workflow_build_executions`)
	s.NoError(err)

	state, ok, err := s.builds.GetWorkflowRerunState(ctx, *wfb.WebhookDeliveryID, wfb.Event, *wfb.WebhookDeliveryID, wfb.FileReference)

	s.Require().NoError(err)
	s.False(ok)
	s.Nil(state)
}

func (s *WorkflowBuildsRepositorySuite) Test_GetWorkflowRerunState_NotFound() {
	ctx := context.Background()

	badWorkflowFileReference := types.WorkflowFileReference{
		Path: "does not exist",
		Ref:  "refs/heads/main",
		SHA:  "da39a3ee5e6b4b0d3255bfef95601890afd80709",
	}

	state, ok, err := s.builds.GetWorkflowRerunState(ctx, "some-id", "push", "some-other-id", badWorkflowFileReference)

	s.Require().NoError(err)
	s.False(ok)
	s.Nil(state)
}

func (s *WorkflowBuildsRepositorySuite) Test_GetDataForTokenRequest_MultiTenant() {
	type testCase struct {
		name                     string
		ghTenantID               int64
		persistInMultiTenantMode bool
		getDataInMultiTenantMode bool
		wfbDBQuery               string
		shouldError              bool
	}

	testCases := []testCase{
		{
			name: "non-multi-tenant",
		},
		{
			name:                     "multi-tenant/wfb-has-valid-ghtenant",
			ghTenantID:               int64(4),
			persistInMultiTenantMode: true,
			getDataInMultiTenantMode: true,
		},
		{
			name:                     "multi-tenant/wfb-missing-ghtenant",
			getDataInMultiTenantMode: true,
			shouldError:              true,
		},
		{
			name:                     "multi-tenant/wfb-has-invalid-ghtenant",
			getDataInMultiTenantMode: true,
			wfbDBQuery:               "update workflow_builds set github_tenant_id = 0 where id = ?",
			shouldError:              true,
		},
	}

	for _, tc := range testCases {
		s.Run(tc.name, func() {

			build, workflowMetadata, checkRunSuite, _ := s.makeBuild()
			checkRunSuite.RepositoryID = types.GlobalID("repo-id")
			perms := &tokens.PermissionSettings{
				InstallationPermissions: *tokens.NewInstallationPermissions(tokens.WritePermissions),
			}

			ctx := context.WithValue(context.Background(), mw.RequestIDKey, string(requestID))
			s.builds = NewWorkflowBuildsRepository(s.adb, s.obs.Logger, s.obs.Statter, s.clock, s.payloads, s.executions, s.globalIDMigrator, tc.persistInMultiTenantMode)
			buildID, _, eventTime, persistedPayload, err := s.builds.Persist(ctx, build, checkRunSuite.RepositoryID, checkRunSuite.EventSHA, checkRunSuite.EventRef, checkRunSuite.FlowIdentifier, workflowMetadata, perms, build.EventPayload, types.NilGlobalID, types.NilGlobalID, ghtenant.GitHubTenant{ID: tc.ghTenantID, Slug: "test"})
			s.NoError(err)
			s.Assert().True(persistedPayload)
			s.Assert().False(eventTime.IsZero())

			err = s.builds.SetCheckSuiteInformation(ctx, buildID, checkRunSuite.CheckSuiteIDPair.GlobalID, checkRunSuite.WorkflowRunID, checkRunSuite.WorkflowRunNumber)
			s.NoError(err)

			s.builds = NewWorkflowBuildsRepository(s.adb, s.obs.Logger, s.obs.Statter, s.clock, s.payloads, s.executions, s.globalIDMigrator, tc.getDataInMultiTenantMode)

			if tc.wfbDBQuery != "" {
				_, err = s.conn.Exec(tc.wfbDBQuery, buildID)
				s.NoError(err)
			}

			loadedState, ok, err := s.builds.GetDataForTokenRequest(ctx, build.ExecutionID.String())

			if tc.shouldError {
				s.Assert().Nil(loadedState)
				s.Assert().False(ok)
				s.Assert().Error(err)
				return
			}

			s.NoError(err)
			s.True(ok)
			perms.DefaultPermissions = tokens.WritePermissions
			s.Equal(perms, loadedState.TokenPermissions)

			if tc.getDataInMultiTenantMode {
				s.Assert().NotNil(loadedState.GitHubTenantID)
				s.Assert().Equal(tc.ghTenantID, *loadedState.GitHubTenantID)
				return
			}

			s.Assert().Nil(loadedState.GitHubTenantID)
		})
	}
}

func (s *WorkflowBuildsRepositorySuite) Test_GetDataForStatusPostback() {

	type testCase struct {
		name                     string
		ghTenantID               int64
		persistInMultiTenantMode bool
		getDataInMultiTenantMode bool
		wfbDBQuery               string
		shouldError              bool
	}

	testCases := []testCase{
		{
			name: "non-multi-tenant",
		},
		{
			name:                     "multi-tenant/wfb-has-valid-ghtenant",
			ghTenantID:               int64(4),
			persistInMultiTenantMode: true,
			getDataInMultiTenantMode: true,
		},
		{
			name:                     "multi-tenant/wfb-missing-ghtenant",
			getDataInMultiTenantMode: true,
			shouldError:              true,
		},
		{
			name:                     "multi-tenant/wfb-has-invalid-ghtenant",
			getDataInMultiTenantMode: true,
			wfbDBQuery:               "update workflow_builds set github_tenant_id = 0 where id = ?",
			shouldError:              true,
		},
	}

	for _, tc := range testCases {
		s.Run(tc.name, func() {

			s.builds = NewWorkflowBuildsRepository(s.adb, s.obs.Logger, s.obs.Statter, s.clock, s.payloads, s.executions, s.globalIDMigrator, tc.persistInMultiTenantMode)

			ctx := context.Background()
			wfb, css, _ := s.persistedCheckRunBuild(ctx, tc.ghTenantID)

			s.builds = NewWorkflowBuildsRepository(s.adb, s.obs.Logger, s.obs.Statter, s.clock, s.payloads, s.executions, s.globalIDMigrator, tc.getDataInMultiTenantMode)

			if tc.wfbDBQuery != "" {
				_, err := s.conn.Exec(tc.wfbDBQuery, css.WorkflowBuildDatabaseID)
				s.NoError(err)
			}

			data, ok, err := s.builds.GetDataForStatusPostback(ctx, wfb.ExecutionID.String())

			if tc.shouldError {
				s.Assert().Nil(data)
				s.Assert().False(ok)
				s.Assert().Error(err)
				return
			}

			s.Require().NoError(err)
			s.True(ok)
			s.Assert().Equal(data.WorkflowBuildDatabaseID, css.WorkflowBuildDatabaseID)

			if tc.getDataInMultiTenantMode {
				s.Assert().NotNil(data.GitHubTenantID)
				s.Assert().Equal(tc.ghTenantID, *data.GitHubTenantID)
				return
			}

			s.Assert().Nil(data.GitHubTenantID)
		})
	}
}

func (s *WorkflowBuildsRepositorySuite) TestGetWorkflowBuildStateByCheckSuiteID() {
	ctx := context.Background()
	_, checkSuiteState, externalBuildID := s.persistedCheckRunBuild(ctx, 0)

	workflow, ok, err := s.builds.GetWorkflowBuildStateByCheckSuiteID(ctx, checkSuiteState.CheckSuiteIDPair.GlobalID)
	s.Require().NoError(err)
	s.Require().True(ok)
	s.Require().NotNil(workflow)

	s.Assert().NotEqual(0, workflow.DatabaseID)
	s.Assert().Nil(workflow.QueuedAt)
	s.Assert().Nil(workflow.CompletedAt)
	s.Assert().Equal(checkSuiteState.FlowIdentifier, workflow.Identifier)
	s.Assert().Equal(checkSuiteState.CheckSuiteIDPair.GlobalID, workflow.CheckSuiteID)
	s.Assert().Equal(externalBuildID, workflow.ExternalBuildID)
	s.Assert().Equal(nextIDFromGlobalID(repositoryID), workflow.RepositoryID)
	s.Assert().Equal(commitSha, workflow.CommitSha)
	s.Assert().Equal(build.WorkflowStateNone, workflow.State)
	s.Assert().Equal(types.WorkflowBackendActionsService, workflow.Backend)
}

func (s *WorkflowBuildsRepositorySuite) TestGetRecentPendingWorkflowBuildStatesByActorIDExcludeRepoIDs() {
	ctx := context.Background()
	excludeRepoIDs := []types.GlobalID{repositoryID, repositoryID2}
	excludeRepoIDsMap := make(map[string]types.GlobalID)
	for i := 0; i < len(excludeRepoIDs); i++ {
		excludeRepoIDsMap[excludeRepoIDs[i].String()] = nextIDFromGlobalID(excludeRepoIDs[i])
	}
	s.mockTwirpClient.EXPECT().GetNextGlobalIDs(mock.Anything, mock.Anything).Return(excludeRepoIDsMap, true, nil)

	_, css, externalBuildID := s.persistedCheckRunBuild(ctx, 0)
	err := s.builds.TransitionToQueued(ctx, css.WorkflowBuildDatabaseID, externalBuildID)
	s.Require().NoError(err)

	workflows, err := s.builds.GetRecentPendingWorkflowBuildStatesByActorIDExcludeRepoIDs(ctx, nextIDFromGlobalID(actorID), excludeRepoIDs, 1, -1)
	s.Require().NoError(err)
	s.Assert().Nil(workflows)

	workflows, err = s.builds.GetRecentPendingWorkflowBuildStatesByActorIDExcludeRepoIDs(ctx, nextIDFromGlobalID(actorID), []types.GlobalID{}, 1, -1)
	s.Require().NoError(err)
	s.Assert().NotNil(workflows)
	s.Assert().Equal(1, len(workflows))

	workflow := workflows[0]
	s.Assert().Equal(nextIDFromGlobalID(actorID), workflow.ActorID)
	s.Assert().Equal(nextIDFromGlobalID(repositoryID), workflow.RepositoryID)
	s.Assert().Equal(build.WorkflowStateQueued, workflow.State)
	s.Assert().NotEqual(0, workflow.DatabaseID)
	s.Assert().NotNil(workflow.QueuedAt)
	s.Assert().Nil(workflow.StartedAt)
	s.Assert().Nil(workflow.CompletedAt)
	s.Assert().Equal(css.FlowIdentifier, workflow.Identifier)
	s.Assert().Equal(externalBuildID, workflow.ExternalBuildID)
	s.Assert().Equal(nextIDFromGlobalID(repositoryID), workflow.RepositoryID)
	s.Assert().Equal(commitSha, workflow.CommitSha)
}

func (s *WorkflowBuildsRepositorySuite) TestGetRecentPendingWorkflowBuildStatesByActorIDExcludeRepoIDs_NextActorIdColumn() {
	ctx := context.Background()
	_, css, externalBuildID := s.persistedCheckRunBuild(ctx, 0)
	err := s.builds.TransitionToQueued(ctx, css.WorkflowBuildDatabaseID, externalBuildID)
	s.Require().NoError(err)

	workflows, err := s.builds.GetRecentPendingWorkflowBuildStatesByActorIDExcludeRepoIDs(ctx, css.ExecutedAsActorID, []types.GlobalID{}, 1, -1)
	s.Require().NoError(err)
	s.Assert().NotNil(workflows)
	s.Assert().Equal(1, len(workflows))
}

func (s *WorkflowBuildsRepositorySuite) Test_GetRecentPendingWorkflowBuildStates_Batchwise() {
	ctx := context.Background()

	_, css, externalBuildID := s.persistedCheckRunBuild(ctx, 0)
	minDBID := css.WorkflowBuildDatabaseID
	err := s.builds.TransitionToQueued(ctx, css.WorkflowBuildDatabaseID, externalBuildID)
	s.Require().NoError(err)

	_, css, externalBuildID = s.persistedCheckRunBuild(ctx, 0)
	nextDBID := css.WorkflowBuildDatabaseID
	err = s.builds.TransitionToQueued(ctx, css.WorkflowBuildDatabaseID, externalBuildID)
	s.Require().NoError(err)

	workflows, err := s.builds.GetRecentPendingWorkflowBuildStatesByActorIDExcludeRepoIDs(ctx, nextIDFromGlobalID(actorID), []types.GlobalID{}, 10, -1)
	s.Require().NoError(err)
	s.Assert().NotNil(workflows)
	s.Assert().Equal(2, len(workflows))
	s.Assert().Equal(minDBID, workflows[0].DatabaseID)
	s.Assert().Equal(nextDBID, workflows[len(workflows)-1].DatabaseID)

	workflows, err = s.builds.GetRecentPendingWorkflowBuildStatesByActorIDExcludeRepoIDs(ctx, nextIDFromGlobalID(actorID), []types.GlobalID{}, 10, minDBID)
	s.Require().NoError(err)
	s.Assert().NotNil(workflows)
	s.Assert().Equal(1, len(workflows))
	s.Assert().Equal(nextDBID, workflows[0].DatabaseID)
}

func (s *WorkflowBuildsRepositorySuite) Test_TransitionTo_IndicatesWhenChanged() {
	ctx := context.Background()

	b, workflowMetadata, checkRunSuite, _ := s.makeBuild()
	id, _, eventTime, persistedPayload, err := s.builds.Persist(
		ctx, b, checkRunSuite.RepositoryID, checkRunSuite.EventSHA,
		checkRunSuite.EventRef, checkRunSuite.FlowIdentifier, workflowMetadata, &tokens.PermissionSettings{}, b.EventPayload, types.NilGlobalID, types.NilGlobalID, ghtenant.GitHubTenant{},
	)
	s.Require().NoError(err)
	s.Assert().True(persistedPayload)
	s.Assert().False(eventTime.IsZero())

	err = s.builds.SetCheckSuiteInformation(ctx, id, checkRunSuite.CheckSuiteIDPair.GlobalID, checkRunSuite.WorkflowRunID, checkRunSuite.WorkflowRunNumber)
	s.Require().NoError(err)

	ok, err := s.builds.TransitionTo(ctx, id, build.WorkflowStateFailed)
	s.Require().NoError(err)
	s.Assert().True(ok, "should have transitioned")

	ok, err = s.builds.TransitionTo(ctx, id, build.WorkflowStateFailed)
	s.Require().NoError(err)
	s.Assert().False(ok, "should not have transitioned when already in state")

	ok, err = s.builds.TransitionTo(ctx, id, build.WorkflowStateStarted)
	s.Require().NoError(err)
	s.Assert().False(ok, "should not have transitioned when attempting to transition to an earlier state")
}

func (s *WorkflowBuildsRepositorySuite) Test_TransitionTo_SetsStartedAt() {
	ctx := context.Background()

	b, checkRunSuite, _ := s.persistedCheckRunBuild(ctx, 0)
	data, ok, err := s.builds.GetDataForStatusPostback(ctx, b.ExecutionID.String())
	s.Require().NoError(err)
	s.Require().True(ok)

	workflow, ok, err := s.builds.GetWorkflowBuildStateByCheckSuiteID(ctx, checkRunSuite.CheckSuiteIDPair.GlobalID)
	s.Require().NoError(err)
	s.Require().True(ok)
	s.Require().NotNil(workflow)

	s.Assert().Nil(workflow.StartedAt)

	ok, err = s.builds.TransitionTo(ctx, data.WorkflowBuildDatabaseID, build.WorkflowStateStarted)
	s.Require().NoError(err)
	s.Assert().True(ok, "should have transitioned to started")

	workflow, ok, err = s.builds.GetWorkflowBuildStateByCheckSuiteID(ctx, checkRunSuite.CheckSuiteIDPair.GlobalID)
	s.Require().NoError(err)
	s.Require().True(ok)
	s.Require().NotNil(workflow)

	s.Assert().NotNil(workflow.StartedAt)
}

func (s *WorkflowBuildsRepositorySuite) Test_TransitionTo_UpdatesWorkflowBuildExecution() {
	ctx := context.Background()
	b, checkRunSuite, _ := s.persistedCheckRunBuild(ctx, 0)

	_, err := s.builds.TransitionTo(ctx, checkRunSuite.WorkflowBuildDatabaseID, build.WorkflowStateStarted)
	s.Require().NoError(err)

	workflow, ok, err := s.builds.GetWorkflowBuildStateByCheckSuiteID(ctx, checkRunSuite.CheckSuiteIDPair.GlobalID)
	s.Require().NoError(err)
	s.Require().True(ok)
	s.Require().NotNil(workflow)
	s.Assert().True(workflow.StartedAt != nil)

	res, err := s.executions.GetByPlanIDForTests(ctx, b.ExecutionID)
	s.NoError(err)

	s.Equal(build.WorkflowStateStarted, res.State)
	s.Assert().True(res.StartedAt != nil)
	s.Equal(workflow.StartedAt, res.StartedAt)
}

func (s *WorkflowBuildsRepositorySuite) Test_TransitionToQueued_SetsQueuedAt() {
	ctx := context.Background()

	b, checkRunSuite, _ := s.persistedCheckRunBuild(ctx, 0)
	data, ok, err := s.builds.GetDataForStatusPostback(ctx, b.ExecutionID.String())
	s.Require().NoError(err)
	s.Require().True(ok)

	workflow, ok, err := s.builds.GetWorkflowBuildStateByCheckSuiteID(ctx, checkRunSuite.CheckSuiteIDPair.GlobalID)
	s.Require().NoError(err)
	s.Require().True(ok)
	s.Require().NotNil(workflow)

	s.Assert().True(workflow.QueuedAt == nil)

	err = s.builds.TransitionToQueued(ctx, data.WorkflowBuildDatabaseID, "123")
	s.Require().NoError(err)

	workflow, ok, err = s.builds.GetWorkflowBuildStateByCheckSuiteID(ctx, checkRunSuite.CheckSuiteIDPair.GlobalID)
	s.Require().NoError(err)
	s.Require().True(ok)
	s.Require().NotNil(workflow)

	s.Assert().True(workflow.QueuedAt != nil)
}

func (s *WorkflowBuildsRepositorySuite) Test_TransitionToQueued_UpdatesExecution() {
	ctx := context.Background()
	b, checkRunSuite, externalBuildID := s.persistedCheckRunBuild(ctx, 0)

	err := s.builds.TransitionToQueued(ctx, checkRunSuite.WorkflowBuildDatabaseID, b.ExternalID)
	s.Require().NoError(err)

	res, err := s.executions.GetByPlanIDForTests(ctx, b.ExecutionID)
	s.NoError(err)

	s.NotNil(res.QueuedAt)
	s.Equal(build.WorkflowStateQueued, res.State)
	s.Equal(externalBuildID, res.ExternalBuildID)
}

func (s *WorkflowBuildsRepositorySuite) Test_SetWasDelayed_UpdatesWorkflowAndExecution() {
	ctx := context.Background()
	b, checkSuiteState, _ := s.persistedCheckRunBuild(ctx, 0)

	err := s.builds.SetWasDelayed(ctx, checkSuiteState.WorkflowRunID)
	s.Require().NoError(err)

	workflow, ok, err := s.builds.GetWorkflowBuildStateByCheckSuiteID(ctx, checkSuiteState.CheckSuiteIDPair.GlobalID)
	s.True(ok)
	s.NoError(err)
	s.True(workflow.WasDelayed)

	execution, err := s.executions.GetByPlanIDForTests(ctx, b.ExecutionID)
	s.NoError(err)
	s.True(execution.WasDelayed)
}

func (s *WorkflowBuildsRepositorySuite) TestGetWorkflowsToHeal() {
	type simpleWorkflowBuild struct {
		uuid        types.WorkflowExecutionID
		createdAt   *time.Time
		completedAt *time.Time
		state       int
		backend     types.WorkflowBackend
	}

	fromHours := 10 * time.Hour
	toHours := 9 * time.Hour

	timeBefore := time.Now().UTC().Add(-fromHours - 10*time.Minute)
	timeDuring := time.Now().UTC().Add(-fromHours + 10*time.Minute)
	timeAfter := time.Now().UTC().Add(-toHours + 10*time.Minute)

	const (
		repoID = types.GlobalID("my-rad-repo")
	)

	insertWorkflowBuild := func(db *sql.DB, wf simpleWorkflowBuild) error {
		r, err := db.Exec(`
					INSERT INTO workflow_builds
					SET
						uuid=?,
						created_at=?,
						completed_at=?,
						state=?,
						repository_id=?,
						check_suite_id=?,
						commit_sha="abc123",
						workflow_id="workflow-id",
						request_id="req123",
						workflow_file_path="path.yaml",
						event="push",
						reporting_metadata='{"repositoryOwner": {"id:": 1}}'`,
			wf.uuid,
			wf.createdAt,
			wf.completedAt,
			wf.state,
			repoID,
			wf.uuid.String(), // put the uuid in the check_suite_id for something unique
		)
		if err != nil {
			return err
		}
		if c, err := r.RowsAffected(); c == 0 || err != nil {
			return errors.Errorf("failed to insert, count %d err %s", c, err)
		}

		buildId, err := r.LastInsertId()
		if err != nil {
			return err
		}

		r, err = db.Exec(`
					INSERT INTO workflow_build_executions
					SET
						workflow_build_id=?,
						plan_id=?,
						created_at=?,
						completed_at=?,
						state=?,
						backend=?`,
			buildId,
			wf.uuid,
			wf.createdAt,
			wf.completedAt,
			wf.state,
			wf.backend,
		)
		if err != nil {
			return err
		}
		if c, err := r.RowsAffected(); c == 0 || err != nil {
			return errors.Errorf("failed to insert, count %d err %s", c, err)
		}
		return nil
	}

	ctx := context.WithValue(context.Background(), mw.RequestIDKey, string(requestID))

	uuidDuring := types.NewRandomWorkflowExecutionID()
	uuidBefore := types.NewRandomWorkflowExecutionID()
	uuidAfter := types.NewRandomWorkflowExecutionID()
	uuidCompleted := types.NewRandomWorkflowExecutionID()
	uuidNotQueued := types.NewRandomWorkflowExecutionID()

	wfs := []simpleWorkflowBuild{
		{
			uuid:      uuidDuring,
			createdAt: &timeDuring,
			state:     2,
			backend:   types.WorkflowBackendActionsService,
		},
		{
			uuid:      uuidBefore,
			createdAt: &timeBefore,
			state:     2,
		},
		{
			uuid:      uuidAfter,
			createdAt: &timeAfter,
			state:     2,
		},
		{
			uuid:        uuidCompleted,
			createdAt:   &timeDuring,
			completedAt: &timeDuring,
			state:       2,
		},
		{
			uuid:  uuidNotQueued,
			state: 2,
		},
	}
	for _, wf := range wfs {
		s.NoError(insertWorkflowBuild(s.conn, wf))
	}

	s.mockTwirpClient.EXPECT().IsFeatureEnabledGlobally(mock.Anything, github.ClampBuildHealingQueriesAfter6Seconds).Return(true)

	res, ok, err := s.buildsRO.GetWorkflowsToHeal(ctx, fromHours, toHours)
	s.True(ok)
	s.NoError(err)
	s.Len(res, 1)
	s.Equal(uuidDuring, res[0].UUID)
}

func (s *WorkflowBuildsRepositorySuite) Test_GetDataForPrejobtoken_Success() {
	ctx := context.Background()

	wfb, css, _ := s.persistedCheckRunBuild(ctx, 0)
	err := s.builds.TransitionToQueued(ctx, css.WorkflowBuildDatabaseID, "azp-id")
	s.Require().NoError(err)

	data, ok, err := s.builds.GetDataForPrejobtoken(ctx, wfb.ExecutionID.String())

	s.Require().NoError(err)
	s.True(ok)
	s.Require().NotNil(data)
	s.Assert().Equal("", data.CustomerLabel)
	s.Assert().Equal(css.WorkflowBuildDatabaseID, data.WorkflowBuildDatabaseID)
	s.Assert().Equal(css.WorkflowRunID, data.WorkflowRunID)
	s.Assert().Equal(wfb.Event, data.Event)
}

func (s *WorkflowBuildsRepositorySuite) Test_GetDataForPrejobtoken_WithCustomerLabel_Success() {
	ctx := context.Background()

	wfb, css, _ := s.persistedCheckRunBuild(ctx, 0, WithCustomerLabel("my-customer-label"))
	err := s.builds.TransitionToQueued(ctx, css.WorkflowBuildDatabaseID, "azp-id")
	s.Require().NoError(err)

	data, ok, err := s.builds.GetDataForPrejobtoken(ctx, wfb.ExecutionID.String())

	s.Require().NoError(err)
	s.True(ok)
	s.Require().NotNil(data)
	s.Assert().Equal("my-customer-label", data.CustomerLabel)
	s.Assert().Equal(css.WorkflowBuildDatabaseID, data.WorkflowBuildDatabaseID)
	s.Assert().Equal(css.WorkflowRunID, data.WorkflowRunID)
	s.Assert().Equal(wfb.Event, data.Event)
}

func (s *WorkflowBuildsRepositorySuite) Test_GetDataForPrejobtoken_NotFound() {
	ctx := context.Background()

	data, ok, err := s.builds.GetDataForPrejobtoken(ctx, uuid.NewString())

	s.Require().NoError(err)
	s.False(ok)
	s.Nil(data)
}

func (s *WorkflowBuildsRepositorySuite) Test_Get_Payload_Success() {
	ctx := context.Background()

	_, css, _ := s.persistedCheckRunBuild(ctx, 0, WithEventPayload([]byte("test")))
	err := s.builds.TransitionToQueued(ctx, css.WorkflowBuildDatabaseID, "azp-id")
	s.Require().NoError(err)

	repoID := types.GlobalID(testutils.EncodeGlobalID("Repository", 789))

	payload, err := s.builds.GetWorkflowBuildPayload(ctx, css.WorkflowBuildDatabaseID, repoID)

	s.Require().NoError(err)
	s.Require().NotNil(payload)
	s.Require().Equal([]byte("test"), payload)
}

func (s *WorkflowBuildsRepositorySuite) Test_PersistWorkflowBuild_EventTooLong_Error() {
	ctx := context.Background()
	triggerEvent := "abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyz"

	opts := []WorkflowBuildOption{
		WithPath("required/1234565/required_workflow/lint/test.yml"),
		WithEvent(triggerEvent),
	}
	ghTenantID := int64(0)

	b, workflowMetadata, checkRunSuite, _ := s.makeBuild(opts...)
	id := uuid.New().String()
	ctx = deliveryguid.WithDeliveryGUID(ctx, &id)

	persistCtx := context.WithValue(ctx, mw.RequestIDKey, string(requestID))
	_, _, _, _, err := s.builds.Persist(
		persistCtx,
		b,
		checkRunSuite.RepositoryID,
		checkRunSuite.EventSHA,
		checkRunSuite.EventRef,
		checkRunSuite.FlowIdentifier,
		workflowMetadata,
		&tokens.PermissionSettings{},
		b.EventPayload,
		nextIDFromGlobalID(actorID),
		nextIDFromGlobalID(actorID),
		ghtenant.GitHubTenant{ID: ghTenantID, Slug: "test-slug"},
	)

	s.Require().Error(err)
}

type WorkflowBuildOption func(b *build.WorkflowBuild, workflowMetadata *hydro_metadata.WorkflowMetadata, checkRunSuite *types.CheckSuiteState)

func WithEventPayload(payload []byte) WorkflowBuildOption {
	return func(b *build.WorkflowBuild, workflowMetadata *hydro_metadata.WorkflowMetadata, checkRunSuite *types.CheckSuiteState) {
		b.EventPayload = payload
	}
}

func WithEvent(event string) WorkflowBuildOption {
	return func(b *build.WorkflowBuild, workflowMetadata *hydro_metadata.WorkflowMetadata, checkRunSuite *types.CheckSuiteState) {
		b.Event = event
	}
}

func WithPath(path string) WorkflowBuildOption {
	return func(b *build.WorkflowBuild, workflowMetadata *hydro_metadata.WorkflowMetadata, checkRunSuite *types.CheckSuiteState) {
		if requiredworkflowutils.IsRequiredWorkflow(path) {
			b.FileReference = types.NewRulesetWorkflowFileReference(path, types.GitRef("refs/heads/main"), types.CommitSha("1234567890"))
		} else {
			b.FileReference = types.NewWorkflowFileReference(path)
		}

		b.WorkflowFilePath = path
		checkRunSuite.WorkflowFilePath = path
	}
}

func WithCustomerLabel(customerLabel string) WorkflowBuildOption {
	return func(b *build.WorkflowBuild, workflowMetadata *hydro_metadata.WorkflowMetadata, checkRunSuite *types.CheckSuiteState) {
		workflowMetadata.CustomerLabel = customerLabel
	}
}

func WithBackend(backend types.WorkflowBackend) WorkflowBuildOption {
	return func(b *build.WorkflowBuild, workflowMetadata *hydro_metadata.WorkflowMetadata, checkRunSuite *types.CheckSuiteState) {
		b.Backend = backend
		checkRunSuite.Backend = backend
	}
}

func WithRootWorkflow(rootWorkflow build.RootWorkflow) WorkflowBuildOption {
	return func(b *build.WorkflowBuild, workflowMetadata *hydro_metadata.WorkflowMetadata, checkRunSuite *types.CheckSuiteState) {
		b.RootWorkflow = rootWorkflow
	}
}

func (s *WorkflowBuildsRepositorySuite) persistedCheckRunBuild(ctx context.Context, ghTenantID int64, opts ...WorkflowBuildOption) (*build.WorkflowBuild, *types.CheckSuiteState, string) {
	b, workflowMetadata, checkRunSuite, externalBuildID := s.makeBuild(opts...)
	id := uuid.New().String()
	ctx = deliveryguid.WithDeliveryGUID(ctx, &id)

	persistCtx := context.WithValue(ctx, mw.RequestIDKey, string(requestID))
	workflowDatabaseID, executionID, eventTime, payloadPersisted, err := s.builds.Persist(
		persistCtx,
		b,
		checkRunSuite.RepositoryID,
		checkRunSuite.EventSHA,
		checkRunSuite.EventRef,
		checkRunSuite.FlowIdentifier,
		workflowMetadata,
		&tokens.PermissionSettings{},
		b.EventPayload,
		nextIDFromGlobalID(actorID),
		nextIDFromGlobalID(actorID),
		ghtenant.GitHubTenant{ID: ghTenantID, Slug: "test-slug"},
	)
	s.Require().NoError(err)
	s.Assert().True(payloadPersisted)
	s.Assert().False(eventTime.IsZero())
	s.Equal(b.ExecutionID, executionID)

	err = s.builds.SetCheckSuiteInformation(ctx, workflowDatabaseID, checkRunSuite.CheckSuiteIDPair.GlobalID, checkRunSuite.WorkflowRunID, checkRunSuite.WorkflowRunNumber)
	s.Require().NoError(err)

	checkRunSuite.WebhookDeliveryID = b.WebhookDeliveryID
	checkRunSuite.WorkflowBuildDatabaseID = workflowDatabaseID
	checkRunSuite.Event = b.Event
	checkRunSuite.EventPayload = b.EventPayload
	checkRunSuite.ExecutedAsActorID = nextIDFromGlobalID(actorID)

	s.Require().NoError(err)
	return b, checkRunSuite, externalBuildID
}

func (s *WorkflowBuildsRepositorySuite) completeBuild(ctx context.Context, css *types.CheckSuiteState) {
	err := s.builds.TransitionToQueued(ctx, css.WorkflowBuildDatabaseID, "some-external-build-id")
	s.Require().NoError(err)
	_, err = s.builds.TransitionTo(ctx, css.WorkflowBuildDatabaseID, build.WorkflowStateSucceeded)
	s.Require().NoError(err)
	err = s.builds.Complete(ctx, time.Now(), time.Now(), css.WorkflowBuildDatabaseID, build.WorkflowStateFailed)
	s.Require().NoError(err)
}

func (s *WorkflowBuildsRepositorySuite) makeBuild(opts ...WorkflowBuildOption) (*build.WorkflowBuild, *hydro_metadata.WorkflowMetadata, *types.CheckSuiteState, string) {
	return makeBuild(s.Suite.T(), opts...)
}

func makeBuild(t *testing.T, opts ...WorkflowBuildOption) (*build.WorkflowBuild, *hydro_metadata.WorkflowMetadata, *types.CheckSuiteState, string) {
	externalBuildID := uuid.New().String()
	executionID := types.NewRandomWorkflowExecutionID()
	checkRunSuite, err := types.NewCheckSuiteState(nextIDFromGlobalID(repositoryID), commitSha, commitRef, checkoutSha, checkoutRef, nextIDFromGlobalID(repositoryID), "test", workflowFilePath, workflowRunID, workflowRunNumber, types.NilGlobalID, "")
	require.NoError(t, err)

	checkRunSuite.ExecutionID = executionID
	checkRunSuite.CheckSuiteIDPair = types.IDPair{
		GlobalID: types.GlobalID(fmt.Sprintf("%scheck-suite-%s", nextIDPrefix, uuid.New().String())),
	}

	webhookDeliveryID := uuid.New().String()
	b := &build.WorkflowBuild{
		ExecutionID:       executionID,
		ExternalID:        externalBuildID,
		WorkflowFilePath:  workflowFilePath,
		WebhookDeliveryID: &webhookDeliveryID,
		Event:             triggerType,
		EventTime:         time.Now().UTC(),
		CheckoutSHA:       checkoutSha,
		CheckoutRef:       checkoutRef,
		Backend:           types.WorkflowBackendActionsService,
	}
	workflowMetadata := &hydro_metadata.WorkflowMetadata{}

	for _, opt := range opts {
		opt(b, workflowMetadata, checkRunSuite)
	}

	fileReference := types.WorkflowFileReference{
		Path: b.WorkflowFilePath,
	}
	b.FileReference = fileReference

	return b, workflowMetadata, checkRunSuite, externalBuildID
}

func newWebhookDeliveryID() *string {
	out := uuid.New().String()
	return &out
}

func (s *WorkflowBuildsRepositorySuite) makeMockBuild() (*build.WorkflowBuild, string) {
	externalBuildID := uuid.New().String()
	b := &build.WorkflowBuild{
		ExecutionID:       types.NewRandomWorkflowExecutionID(),
		ExternalID:        externalBuildID,
		WorkflowFilePath:  workflowFilePath,
		Event:             triggerType,
		WebhookDeliveryID: newWebhookDeliveryID(),
	}
	return b, externalBuildID
}

// https://github.com/github/c2c-actions-experience/issues/6602 is tracking the removal of this function
func nextIDFromGlobalID(legacyGID types.GlobalID) types.GlobalID {
	return types.GlobalID(fmt.Sprintf("%s%s", nextIDPrefix, legacyGID))
}

func TestWorkflowBuildsRepositorySuite(t *testing.T) {
	testutils.NoShort(t)
	suite.Run(t, new(WorkflowBuildsRepositorySuite))
}

func (s *WorkflowBuildsRepositorySuite) TestPersistForRequiredWorkflows() {
	build, workflowMetadata, checkRunSuite, _ := s.makeBuild(WithPath("required/12345/required_workflows/test.yml"))
	checkRunSuite.RepositoryID = types.GlobalID("repo-id")
	perms := &tokens.PermissionSettings{
		InstallationPermissions: tokens.InstallationPermissions{
			Checks:       tokens.WriteAccess,
			Issues:       tokens.WriteAccess,
			PullRequests: tokens.ReadAccess,
		},
		DefaultPermissions: tokens.WritePermissions,
	}

	ctx := context.WithValue(context.Background(), mw.RequestIDKey, string(requestID))
	buildID, _, eventTime, persistedPayload, err := s.builds.Persist(ctx, build, checkRunSuite.RepositoryID, checkRunSuite.EventSHA, checkRunSuite.EventRef, checkRunSuite.FlowIdentifier, workflowMetadata, perms, build.EventPayload, types.NilGlobalID, types.NilGlobalID, ghtenant.GitHubTenant{})
	s.NoError(err)
	s.Assert().True(persistedPayload)
	s.Assert().False(eventTime.IsZero())

	rows := s.conn.QueryRow(`select workflow_file_path, imposer_repository_id from workflow_builds where id = ?`, buildID)

	var path string
	var imposerRepositoryID int64
	s.Require().NoError(rows.Scan(&path, &imposerRepositoryID))
	s.Assert().Equal("required_workflows/test.yml", path)
	s.Assert().Equal(int64(12345), imposerRepositoryID)

	// Try persisting the same data again
	buildID, _, eventTime, persistedPayload, err = s.builds.Persist(ctx, build, checkRunSuite.RepositoryID, checkRunSuite.EventSHA, checkRunSuite.EventRef, checkRunSuite.FlowIdentifier, workflowMetadata, perms, build.EventPayload, types.NilGlobalID, types.NilGlobalID, ghtenant.GitHubTenant{})
	s.NoError(err)
	s.Assert().True(persistedPayload)
	s.Assert().False(eventTime.IsZero())
}

func (s *WorkflowBuildsRepositorySuite) TestPersistForRequiredWorkflowsAlongWithNormalWorkflows() {
	build, workflowMetadata, checkRunSuite, _ := s.makeBuild(WithPath("required/12345/.github/workflows/test.yml"))
	checkRunSuite.RepositoryID = types.GlobalID("repo-id")
	perms := &tokens.PermissionSettings{
		InstallationPermissions: tokens.InstallationPermissions{
			Checks:       tokens.WriteAccess,
			Issues:       tokens.WriteAccess,
			PullRequests: tokens.ReadAccess,
		},
		DefaultPermissions: tokens.WritePermissions,
	}

	ctx := context.WithValue(context.Background(), mw.RequestIDKey, string(requestID))
	_, _, eventTime, persistedPayload, err := s.builds.Persist(ctx, build, checkRunSuite.RepositoryID, checkRunSuite.EventSHA, checkRunSuite.EventRef, checkRunSuite.FlowIdentifier, workflowMetadata, perms, build.EventPayload, types.NilGlobalID, types.NilGlobalID, ghtenant.GitHubTenant{})
	s.NoError(err)
	s.Assert().True(persistedPayload)
	s.Assert().False(eventTime.IsZero())

	build, workflowMetadata, checkRunSuite, _ = s.makeBuild(WithPath(".github/workflows/test.yml"))
	_, _, eventTime, persistedPayload, err = s.builds.Persist(ctx, build, checkRunSuite.RepositoryID, checkRunSuite.EventSHA, checkRunSuite.EventRef, checkRunSuite.FlowIdentifier, workflowMetadata, perms, build.EventPayload, types.NilGlobalID, types.NilGlobalID, ghtenant.GitHubTenant{})
	s.NoError(err)
	s.Assert().True(persistedPayload)
	s.Assert().False(eventTime.IsZero())

	row := s.conn.QueryRow(`select workflow_file_path, imposer_repository_id from workflow_builds where workflow_file_path = ".github/workflows/test.yml" and imposer_repository_id=12345`)

	var path string
	var imposerRepositoryID int64
	s.Require().NoError(row.Scan(&path, &imposerRepositoryID))
	s.Assert().Equal(".github/workflows/test.yml", path)
	s.Assert().Equal(int64(12345), imposerRepositoryID)

	row = s.conn.QueryRow(`select workflow_file_path, imposer_repository_id from workflow_builds where workflow_file_path = ".github/workflows/test.yml" and imposer_repository_id=0`)
	s.Require().NoError(row.Scan(&path, &imposerRepositoryID))
	s.Assert().Equal(".github/workflows/test.yml", path)
}

func (s *WorkflowBuildsRepositorySuite) Test_GetWorkflowState_RequiredWorkflows() {
	ctx := context.Background()

	rootWorkflow := build.RootWorkflow{
		FilePath:           "required/1234565/required_workflow/lint/test.yml",
		Ref:                "heads/refs/main",
		SHA:                "abc",
		IsRequiredWorkflow: true,
	}

	wfb, css, _ := s.persistedCheckRunBuild(ctx, 0, WithPath("required/1234565/required_workflow/lint/test.yml"), WithRootWorkflow(rootWorkflow))
	err := s.builds.TransitionToQueued(ctx, css.WorkflowBuildDatabaseID, "azp-id")
	s.Require().NoError(err)

	state, ok, err := s.builds.GetWorkflowState(ctx, *wfb.WebhookDeliveryID, wfb.Event, wfb.FileReference)

	s.Require().NoError(err)
	s.True(ok)
	s.Require().NotNil(state)
	s.Assert().Equal(build.WorkflowStateQueued, *state)
}

func (s *WorkflowBuildsRepositorySuite) Test_GetWorkflowState_RequiredWorkflows_ff_off() {
	ctx := context.Background()

	rootWorkflow := build.RootWorkflow{
		FilePath:           "required/1234565/required_workflow/lint/test.yml",
		Ref:                "heads/refs/main",
		SHA:                "abc",
		IsRequiredWorkflow: true,
	}

	wfb, css, _ := s.persistedCheckRunBuild(ctx, 0, WithPath("required/1234565/required_workflow/lint/test.yml"), WithRootWorkflow(rootWorkflow))
	err := s.builds.TransitionToQueued(ctx, css.WorkflowBuildDatabaseID, "azp-id")
	s.Require().NoError(err)

	state, ok, err := s.builds.GetWorkflowState(ctx, *wfb.WebhookDeliveryID, wfb.Event, wfb.FileReference)

	s.Require().NoError(err)
	s.True(ok)
	s.Require().NotNil(state)
	s.Assert().Equal(build.WorkflowStateQueued, *state)
}

func (s *WorkflowBuildsRepositorySuite) Test_GetWorkflowRerunState_RequiredWorkflows() {
	ctx := context.Background()

	rootWorkflow := build.RootWorkflow{
		FilePath:           "required/1234565/required_workflow/lint/test.yml",
		Ref:                "heads/refs/main",
		SHA:                "abc",
		IsRequiredWorkflow: true,
	}

	wfb, css, _ := s.persistedCheckRunBuild(ctx, 0, WithPath("required/1234565/required_workflow/lint/test.yml"), WithRootWorkflow(rootWorkflow))
	err := s.builds.TransitionToQueued(ctx, css.WorkflowBuildDatabaseID, "azp-id")
	s.Require().NoError(err)

	state, ok, err := s.builds.GetWorkflowRerunState(ctx, *wfb.WebhookDeliveryID, wfb.Event, *wfb.WebhookDeliveryID, wfb.FileReference)

	s.Require().NoError(err)
	s.True(ok)
	s.Require().NotNil(state)
	s.Assert().Equal(build.WorkflowStateQueued, *state)
}

func (s *WorkflowBuildsRepositorySuite) Test_GetWorkflowRerunState_RequiredWorkflows_ff_off() {
	ctx := context.Background()

	rootWorkflow := build.RootWorkflow{
		FilePath:           "required/1234565/required_workflow/lint/test.yml",
		Ref:                "heads/refs/main",
		SHA:                "abc",
		IsRequiredWorkflow: true,
	}

	wfb, css, _ := s.persistedCheckRunBuild(ctx, 0, WithPath("required/1234565/required_workflow/lint/test.yml"), WithRootWorkflow(rootWorkflow))
	err := s.builds.TransitionToQueued(ctx, css.WorkflowBuildDatabaseID, "azp-id")
	s.Require().NoError(err)

	state, ok, err := s.builds.GetWorkflowRerunState(ctx, *wfb.WebhookDeliveryID, wfb.Event, *wfb.WebhookDeliveryID, wfb.FileReference)

	s.Require().NoError(err)
	s.True(ok)
	s.Require().NotNil(state)
	s.Assert().Equal(build.WorkflowStateQueued, *state)
}

func (s *WorkflowBuildsRepositorySuite) TestGetStateByCheckSuiteIDForRequiredWorkflows() {
	ctx := context.Background()
	_, checkSuiteState, _ := s.persistedCheckRunBuild(ctx, 0, WithPath("required/4566/required_workflows/lint/linter.yml"), WithEventPayload([]byte("test")))

	storedState, ok, err := s.builds.GetStateByCheckSuiteID(ctx, checkSuiteState.CheckSuiteIDPair.GlobalID)
	s.Require().NoError(err)
	s.True(ok)
	s.Assert().Equal(checkSuiteState, storedState)
}

func (s *WorkflowBuildsRepositorySuite) TestGetWorkflowBuildStateByCheckSuiteIDForRequiredWorkflows() {
	ctx := context.Background()
	_, checkSuiteState, externalBuildID := s.persistedCheckRunBuild(ctx, 0, WithPath("required/4566/required_workflows/lint/linter.yml"))

	workflow, ok, err := s.builds.GetWorkflowBuildStateByCheckSuiteID(ctx, checkSuiteState.CheckSuiteIDPair.GlobalID)
	s.Require().NoError(err)
	s.Require().True(ok)
	s.Require().NotNil(workflow)

	s.Assert().NotEqual(0, workflow.DatabaseID)
	s.Assert().Nil(workflow.QueuedAt)
	s.Assert().Nil(workflow.CompletedAt)
	s.Assert().Equal(checkSuiteState.FlowIdentifier, workflow.Identifier)
	s.Assert().Equal(checkSuiteState.CheckSuiteIDPair.GlobalID, workflow.CheckSuiteID)
	s.Assert().Equal(externalBuildID, workflow.ExternalBuildID)
	s.Assert().Equal(nextIDFromGlobalID(repositoryID), workflow.RepositoryID)
	s.Assert().Equal(commitSha, workflow.CommitSha)
	s.Assert().Equal(build.WorkflowStateNone, workflow.State)
	s.Assert().Equal("required/4566/required_workflows/lint/linter.yml", checkSuiteState.WorkflowFilePath)
	s.Assert().Equal(types.WorkflowBackendActionsService, workflow.Backend)
}

func (s *WorkflowBuildsRepositorySuite) Test_GetDataForStatusPostback_RequiredWorkflows() {
	ctx := context.Background()

	wfb, css, _ := s.persistedCheckRunBuild(ctx, 0, WithPath("required/4566/required_workflows/lint/linter.yml"))
	data, ok, err := s.builds.GetDataForStatusPostback(ctx, wfb.ExecutionID.String())
	s.Require().NoError(err)
	s.True(ok)
	s.Assert().Equal(data.WorkflowBuildDatabaseID, css.WorkflowBuildDatabaseID)
	s.Assert().Equal("required/4566/required_workflows/lint/linter.yml", data.CheckSuiteState.WorkflowFilePath)
}

func (s *WorkflowBuildsRepositorySuite) TestGetDataForTokenRequest_RequiredWorkflows() {
	build, workflowMetadata, checkRunSuite, _ := s.makeBuild(WithPath("required/4566/required_workflows/lint/linter.yml"))
	checkRunSuite.RepositoryID = types.GlobalID("repo-id")
	perms := &tokens.PermissionSettings{
		InstallationPermissions: tokens.InstallationPermissions{
			Checks:       tokens.WriteAccess,
			Issues:       tokens.WriteAccess,
			PullRequests: tokens.ReadAccess,
		},
		DefaultPermissions: tokens.WritePermissions,
	}

	ctx := context.WithValue(context.Background(), mw.RequestIDKey, string(requestID))
	buildID, _, eventTime, persistedPayload, err := s.builds.Persist(ctx, build, checkRunSuite.RepositoryID, checkRunSuite.EventSHA, checkRunSuite.EventRef, checkRunSuite.FlowIdentifier, workflowMetadata, perms, build.EventPayload, types.NilGlobalID, types.NilGlobalID, ghtenant.GitHubTenant{})
	s.NoError(err)
	s.Assert().True(persistedPayload)
	s.Assert().False(eventTime.IsZero())

	err = s.builds.SetCheckSuiteInformation(ctx, buildID, checkRunSuite.CheckSuiteIDPair.GlobalID, checkRunSuite.WorkflowRunID, checkRunSuite.WorkflowRunNumber)
	s.NoError(err)

	loadedState, ok, err := s.builds.GetDataForTokenRequest(ctx, build.ExecutionID.String())
	s.NoError(err)
	s.True(ok)
	s.Equal(perms, loadedState.TokenPermissions)
	s.Equal("required/4566/required_workflows/lint/linter.yml", loadedState.WorkflowFilePath)
}

func (s *WorkflowBuildsRepositorySuite) TestGetWorkflowsToHeal_RequiredWorkflows() {
	type simpleWorkflowBuild struct {
		uuid        types.WorkflowExecutionID
		createdAt   *time.Time
		completedAt *time.Time
		state       int
		backend     types.WorkflowBackend
	}

	fromHours := 10 * time.Hour
	toHours := 9 * time.Hour

	timeBefore := time.Now().UTC().Add(-fromHours - 10*time.Minute)
	timeDuring := time.Now().UTC().Add(-fromHours + 10*time.Minute)
	timeAfter := time.Now().UTC().Add(-toHours + 10*time.Minute)

	const (
		repoID = types.GlobalID("my-rad-repo")
	)

	insertWorkflowBuild := func(db *sql.DB, wf simpleWorkflowBuild) error {
		r, err := db.Exec(`
						INSERT INTO workflow_builds
						SET
							uuid=?,
							created_at=?,
							completed_at=?,
							state=?,
							repository_id=?,
							check_suite_id=?,
							commit_sha="abc123",
							workflow_id="workflow-id",
							request_id="req123",
							workflow_file_path="required_workflows/lint/linter.yml",
							imposer_repository_id=4566,
							event="push"`,
			wf.uuid,
			wf.createdAt,
			wf.completedAt,
			wf.state,
			repoID,
			wf.uuid.String(), // put the uuid in the check_suite_id for something unique
		)
		if err != nil {
			return err
		}
		if c, err := r.RowsAffected(); c == 0 || err != nil {
			return errors.Errorf("failed to insert, count %d err %s", c, err)
		}

		buildId, err := r.LastInsertId()
		if err != nil {
			return err
		}

		r, err = db.Exec(`
						INSERT INTO workflow_build_executions
						SET
							workflow_build_id=?,
							plan_id=?,
							created_at=?,
							completed_at=?,
							state=?,
							backend=?`,
			buildId,
			wf.uuid,
			wf.createdAt,
			wf.completedAt,
			wf.state,
			wf.backend,
		)
		if err != nil {
			return err
		}
		if c, err := r.RowsAffected(); c == 0 || err != nil {
			return errors.Errorf("failed to insert, count %d err %s", c, err)
		}
		return nil
	}

	ctx := context.WithValue(context.Background(), mw.RequestIDKey, string(requestID))

	uuidDuring := types.NewRandomWorkflowExecutionID()
	uuidBefore := types.NewRandomWorkflowExecutionID()
	uuidAfter := types.NewRandomWorkflowExecutionID()
	uuidCompleted := types.NewRandomWorkflowExecutionID()
	uuidNotQueued := types.NewRandomWorkflowExecutionID()

	wfs := []simpleWorkflowBuild{
		{
			uuid:      uuidDuring,
			createdAt: &timeDuring,
			state:     2,
			backend:   types.WorkflowBackendActionsService,
		},
		{
			uuid:      uuidBefore,
			createdAt: &timeBefore,
			state:     2,
		},
		{
			uuid:      uuidAfter,
			createdAt: &timeAfter,
			state:     2,
		},
		{
			uuid:        uuidCompleted,
			createdAt:   &timeDuring,
			completedAt: &timeDuring,
			state:       2,
		},
		{
			uuid:  uuidNotQueued,
			state: 2,
		},
	}
	for _, wf := range wfs {
		s.NoError(insertWorkflowBuild(s.conn, wf))
	}

	s.mockTwirpClient.EXPECT().IsFeatureEnabledGlobally(mock.Anything, github.ClampBuildHealingQueriesAfter6Seconds).Return(true)

	res, ok, err := s.buildsRO.GetWorkflowsToHeal(ctx, fromHours, toHours)
	s.True(ok)
	s.NoError(err)
	s.Len(res, 1)
	s.Equal(uuidDuring, res[0].UUID)
	s.Equal("required/4566/required_workflows/lint/linter.yml", res[0].WorkflowFilePath)
}

func Test_trimWorkflowId(t *testing.T) {
	tests := []struct {
		name          string
		before        string
		expectedAfter string
	}{
		{
			name:          "within length bounds",
			before:        "Run My CI",
			expectedAfter: "Run My CI",
		},
		{
			name:          "exceeds length bounds",
			before:        "npm_and_yarn in /frontend for babel-traverse, braces, braces, debug, debug, express, follow-redirects, follow-redirects, fresh, glob-parent, jquery, jquery, jquery, jquery, jquery, json5, loader-utils, mime, minimist, minimist, minimist, minimist, ms, next, next, next, next, next, node-fetch, node-fetch, open, webpack-dev-middleware, webpack-dev-server - Update #10451",
			expectedAfter: "npm_and_yarn in /frontend for babel-traverse, braces, braces, debug, debug, express, follow-redirects, follow-redirects, fresh, glob-parent, jquery, jquery, jquery, jquery, jquery, json5, loader-utils, mime, minimist, minimist, minimist, minimist, ms, nex",
		},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			got := trimVarCharColumnData(tc.before, 255)
			if tc.expectedAfter != got {
				t.Errorf("trimWorkflowId(%s)=%s, expected %s", tc.name, got, tc.expectedAfter)
			}
		})
	}
}
