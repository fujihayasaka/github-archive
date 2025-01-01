package deployer

import (
	"context"
	"os"
	"testing"

	"github.com/facebookgo/clock"
	"github.com/google/uuid"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/suite"

	"github.com/github/launch/clients/ghtwirp"
	metadata "github.com/github/launch/clients/hydro/metadata"
	"github.com/github/launch/mysqldb"
	"github.com/github/launch/observability"
	"github.com/github/launch/observability/logger"
	"github.com/github/launch/observability/statter"
	"github.com/github/launch/types"
	"github.com/github/launch/utils/asql"
	"github.com/github/launch/utils/testutils"
	build "github.com/github/launch/workflowbuild/build"
)

type WorkflowBuildExecutionsRepositorySuite struct {
	suite.Suite
	conn             *asql.SQL
	clock            clock.Clock
	repo             *workflowBuildExecutionsRepository
	globalIDMigrator GlobalIDMigrator
	mockTwirpClient  *ghtwirp.MockClient
}

func TestWorkflowBuildExecutionsRepository(t *testing.T) {
	testutils.NoShort(t)
	suite.Run(t, new(WorkflowBuildExecutionsRepositorySuite))
}

func (s *WorkflowBuildExecutionsRepositorySuite) SetupSuite() {
	conn, err := mysqldb.NewDB(statter.NullStatter(), os.Getenv("LAUNCH_DEPLOYER_TEST_DATABASE_URL"))
	s.Require().NoError(err)
	s.conn = asql.New(conn, logger.TestLogger(), statter.NullStatter(), testutils.NewNoopBreaker(), asql.LaunchCluster)
	s.clock = clock.NewMock()
	s.mockTwirpClient = ghtwirp.NewMockClient(s.T())
	s.globalIDMigrator = NewGlobalIDMigrator(s.mockTwirpClient)

	s.repo = &workflowBuildExecutionsRepository{
		db:          s.conn,
		obs:         observability.NewTestObservability(),
		clock:       s.clock,
		gidMigrator: s.globalIDMigrator,
	}
}

func (s *WorkflowBuildExecutionsRepositorySuite) SetupTest() {
	_, err := s.conn.Conn().Exec(`TRUNCATE workflow_build_executions`)

	s.mockTwirpClient.EXPECT().GetNextGlobalID(mock.Anything, mock.Anything).Return(nextIDFromGlobalID(actorID), nil)

	s.Require().NoError(err)
}

func (s *WorkflowBuildExecutionsRepositorySuite) Test_Persist() {
	ctx := context.Background()
	now := s.clock.Now().UTC()
	build, _, _, _ := s.makeBuild()

	dbID, err := s.repo.Persist(ctx, build, 123, actorID, 1, exampleMD)
	s.NoError(err)
	s.NotNil(dbID)

	res, err := s.repo.GetByPlanIDForTests(ctx, build.ExecutionID)
	s.NoError(err)
	s.Equal(build.ExecutionID, res.PlanID)
	s.Equal(build.ExternalID, res.ExternalBuildID)
	s.Equal(build.WebhookDeliveryID, res.WebhookDeliveryID)
	s.Equal(int64(123), res.WorkflowBuildID)
	s.Equal(nextIDFromGlobalID(actorID), res.TriggeringActorID)
	s.Equal(1, res.Attempt)
	s.Equal(false, res.WasDelayed)
	s.Equal(exampleMD, res.WorkflowMetadata)
	s.Equal(build.WebhookDeliveryID, res.WebhookDeliveryID)
	s.Equal(build.Backend, res.Backend)
	s.Nil(res.QueuedAt)
	s.Nil(res.StartedAt)
	s.Nil(res.CompletedAt)
	s.Equal(&now, res.CreatedAt)
}

func (s *WorkflowBuildExecutionsRepositorySuite) Test_Persist_ConvertsLegacyGids() {
	ctx := context.Background()
	build, _, _, _ := s.makeBuild()

	// Reset all mocks so we can test the legacy gid conversion
	s.mockTwirpClient.ExpectedCalls = []*mock.Call{}
	s.mockTwirpClient.EXPECT().GetNextGlobalID(mock.Anything, mock.Anything).Return(nextIDFromGlobalID(actorID), nil)

	dbID, err := s.repo.Persist(ctx, build, 123, actorID, 1, exampleMD)
	s.NoError(err)
	s.NotNil(dbID)

	res, err := s.repo.GetByPlanIDForTests(ctx, build.ExecutionID)
	s.NoError(err)
	s.Equal(nextIDFromGlobalID(actorID), res.TriggeringActorID)
}

func (s *WorkflowBuildExecutionsRepositorySuite) Test_PersistIdempotency() {
	ctx := context.Background()
	build, _, _, _ := s.makeBuild()

	dbID, err := s.repo.Persist(ctx, build, 123, actorID, 1, exampleMD)
	s.NoError(err)
	s.NotNil(dbID)

	build.ExecutionID = types.NewRandomWorkflowExecutionID() // We will have a new executionID (planID) if we get the webhook again

	dbID2, err := s.repo.Persist(ctx, build, 123, actorID, 1, exampleMD)
	s.NoError(err)
	s.Equal(dbID, dbID2)
}

func (s *WorkflowBuildExecutionsRepositorySuite) Test_PersistError() {
	ctx := context.Background()
	planID := types.NewRandomWorkflowExecutionID()
	now := s.clock.Now().UTC()

	dbID, err := s.repo.PersistError(ctx, planID, 123, actorID, 1, now)
	s.NoError(err)
	s.NotNil(dbID)

	res, err := s.repo.GetByPlanIDForTests(ctx, planID)
	s.NoError(err)
	s.Equal(planID, res.PlanID)
	s.Equal("", res.ExternalBuildID)
	s.Equal(int64(123), res.WorkflowBuildID)
	s.Equal(nextIDFromGlobalID(actorID), res.TriggeringActorID)
	s.Equal(1, res.Attempt)
	s.Equal(build.WorkflowStateFailed, res.State)
	s.Equal(false, res.WasDelayed)
	s.Nil(res.QueuedAt)
	s.Nil(res.StartedAt)
	s.Equal(&now, res.CompletedAt)
	s.Equal(&now, res.CreatedAt)
}

func (s *WorkflowBuildExecutionsRepositorySuite) Test_PersistError_ConvertsLegacyGids() {
	ctx := context.Background()
	planID := types.NewRandomWorkflowExecutionID()
	now := s.clock.Now().UTC()

	// Reset all mocks so we can test the legacy gid conversion
	s.mockTwirpClient.ExpectedCalls = []*mock.Call{}
	s.mockTwirpClient.EXPECT().GetNextGlobalID(mock.Anything, mock.Anything).Return(nextIDFromGlobalID(actorID), nil)

	dbID, err := s.repo.PersistError(ctx, planID, 123, actorID, 1, now)
	s.NoError(err)
	s.NotNil(dbID)

	res, err := s.repo.GetByPlanIDForTests(ctx, planID)
	s.NoError(err)
	s.Equal(nextIDFromGlobalID(actorID), res.TriggeringActorID)
}

func (s *WorkflowBuildExecutionsRepositorySuite) Test_Complete() {
	ctx := context.Background()
	b, _, _, _ := s.makeBuild()

	_, err := s.repo.Persist(ctx, b, 123, actorID, 1, exampleMD)
	s.NoError(err)

	now := s.clock.Now().UTC()
	err = s.repo.Complete(ctx, 123, now, now, build.WorkflowStateSucceeded)
	s.NoError(err)

	res, err := s.repo.GetByPlanIDForTests(ctx, b.ExecutionID)
	s.NoError(err)

	s.Equal(int64(123), res.WorkflowBuildID)
	s.Equal(build.WorkflowStateSucceeded, res.State)
	s.Equal(&now, res.CompletedAt)
}

func (s *WorkflowBuildExecutionsRepositorySuite) Test_TransitionToQueued() {
	ctx := context.Background()
	b, _, _, _ := s.makeBuild()

	_, err := s.repo.Persist(ctx, b, 123, actorID, 1, exampleMD)
	s.NoError(err)

	now := s.clock.Now().UTC()
	newExternalBuildID := uuid.New().String()
	err = s.repo.TransitionToQueued(ctx, 123, newExternalBuildID, now)
	s.NoError(err)

	res, err := s.repo.GetByPlanIDForTests(ctx, b.ExecutionID)
	s.NoError(err)

	s.Equal(build.WorkflowStateQueued, res.State)
	s.Equal(newExternalBuildID, res.ExternalBuildID)
	s.Equal(&now, res.QueuedAt)
}

func (s *WorkflowBuildExecutionsRepositorySuite) Test_SetWasDelayed() {
	ctx := context.Background()
	b, _, _, _ := s.makeBuild()

	_, err := s.repo.Persist(ctx, b, 123, actorID, 1, exampleMD)
	s.NoError(err)

	err = s.repo.SetWasDelayed(ctx, 123)
	s.NoError(err)

	res, err := s.repo.GetByPlanIDForTests(ctx, b.ExecutionID)
	s.NoError(err)

	s.True(res.WasDelayed)
}

func (s *WorkflowBuildExecutionsRepositorySuite) Test_TransitionTo_Started() {
	ctx := context.Background()
	b, _, _, _ := s.makeBuild()

	_, err := s.repo.Persist(ctx, b, 123, actorID, 1, exampleMD)
	s.NoError(err)

	now := s.clock.Now().UTC()
	err = s.repo.TransitionTo(ctx, 123, build.WorkflowStateStarted, now)
	s.NoError(err)

	res, err := s.repo.GetByPlanIDForTests(ctx, b.ExecutionID)
	s.NoError(err)

	s.Equal(&now, res.StartedAt)
	s.Equal(build.WorkflowStateStarted, res.State)
}

func (s *WorkflowBuildExecutionsRepositorySuite) Test_TransitionTo_NeverStarted() {
	ctx := context.Background()
	b, _, _, _ := s.makeBuild()

	_, err := s.repo.Persist(ctx, b, 123, actorID, 1, exampleMD)
	s.NoError(err)

	now := s.clock.Now().UTC()
	err = s.repo.TransitionTo(ctx, 123, build.WorkflowStateNeverStarted, now)
	s.NoError(err)

	res, err := s.repo.GetByPlanIDForTests(ctx, b.ExecutionID)
	s.NoError(err)

	s.Nil(res.StartedAt)
	s.Equal(build.WorkflowStateNeverStarted, res.State)
}

func (s *WorkflowBuildExecutionsRepositorySuite) Test_TransitionToError() {
	ctx := context.Background()
	b, _, _, _ := s.makeBuild()

	_, err := s.repo.Persist(ctx, b, 123, actorID, 1, exampleMD)
	s.NoError(err)

	now := s.clock.Now().UTC()
	err = s.repo.TransitionToError(ctx, 123, now)
	s.NoError(err)

	res, err := s.repo.GetByPlanIDForTests(ctx, b.ExecutionID)
	s.NoError(err)

	s.Equal(build.WorkflowStateFailed, res.State)
	s.Equal(&now, res.CompletedAt)
}

func (s *WorkflowBuildExecutionsRepositorySuite) Test_StateInList() {
	res := stateInList(build.WorkflowStateFailed)

	s.Equal([]any{0, 1, 2, 3}, res)
}

func (s *WorkflowBuildExecutionsRepositorySuite) makeBuild(opts ...WorkflowBuildOption) (*build.WorkflowBuild, *metadata.WorkflowMetadata, *types.CheckSuiteState, string) {
	return makeBuild(s.Suite.T(), opts...)
}
