package deployer

import (
	"context"
	"database/sql"
	"os"
	"testing"

	"github.com/facebookgo/clock"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/suite"

	"github.com/github/launch/clients/ghtwirp"
	"github.com/github/launch/db/stores/payloads"
	"github.com/github/launch/mysqldb"
	"github.com/github/launch/observability"
	"github.com/github/launch/observability/statter"
	"github.com/github/launch/types"
	"github.com/github/launch/utils/asql"
	"github.com/github/launch/utils/testutils"
	"github.com/github/launch/workflowbuild/build"
)

type PersistErrorTestSuite struct {
	suite.Suite

	builds     *workflowBuildsRepository
	repoID     types.GlobalID
	repoNextID types.GlobalID

	executions       WorkflowBuildExecutionsRepository
	globalIDMigrator GlobalIDMigrator
	mockTwirpClient  *ghtwirp.MockClient
	conn             *sql.DB
}

const (
	ExecutingActorID      = types.GlobalID("MDQ6VXNlcjE=")
	ExecutingActorNextID  = types.GlobalID("U_kgAB")
	TriggeringActorID     = types.GlobalID("MDQ6VXNlcjE4NDg3MjQx")
	TriggeringActorNextID = types.GlobalID("U_kgDOARoXyQ")
)

func TestPersistErrorTestSuite(t *testing.T) {
	suite.Run(t, new(PersistErrorTestSuite))
}

func (s *PersistErrorTestSuite) SetupTest() {
	payloadsConn, err := mysqldb.NewDB(statter.NullStatter(), os.Getenv("ACTIONS_PAYLOADS_TEST_DATABASE_URL"))
	s.Require().NoError(err)
	testConn, err := mysqldb.NewDB(statter.NullStatter(), os.Getenv("LAUNCH_DEPLOYER_TEST_DATABASE_URL"))
	s.conn = testConn
	s.Require().NoError(err)
	clock := clock.NewMock()

	obs := observability.NewTestObservability()

	pdb := asql.New(payloadsConn, obs.Logger, obs.Statter, testutils.NewNoopBreaker(), asql.PayloadsCluster)
	payloadsModel := payloads.New(pdb, obs.Logger, obs.Statter)
	adb := asql.New(s.conn, obs.Logger, obs.Statter, testutils.NewNoopBreaker(), asql.LaunchCluster)
	s.mockTwirpClient = ghtwirp.NewMockClient(s.T())
	s.globalIDMigrator = NewGlobalIDMigrator(s.mockTwirpClient)
	s.executions = NewWorkflowBuildExecutionsRepository(adb, obs, clock, s.globalIDMigrator)
	builds := NewWorkflowBuildsRepository(adb, obs.Logger, obs.Statter, clock, payloadsModel, s.executions, s.globalIDMigrator, false)

	s.repoID = types.GlobalID(testutils.EncodeGlobalID("Repository", 1337))
	s.repoNextID = types.GlobalID("R_kgDNBTk")

	_, err = s.conn.Exec(`delete from workflow_builds where repository_id = ?`, s.repoID.String())
	s.Require().NoError(err)
	_, err = s.conn.Exec(`delete from workflow_builds where check_suite_next_id = ?`, "CS_kwDOAROBws4ZHvcg")
	s.Require().NoError(err)

	s.builds = builds
}

func (s *PersistErrorTestSuite) Test_WorkflowBuildsRepository_PersistWithoutChecksuite() {
	s.mockTwirpClient.EXPECT().GetNextGlobalID(mock.Anything, s.repoID.String()).Return(s.repoNextID, nil)
	s.mockTwirpClient.EXPECT().GetNextGlobalID(mock.Anything, "").Return(types.NilGlobalID, nil)

	ctx := context.Background()
	_, err := s.builds.PersistError(
		ctx, s.repoID, types.NewRandomWorkflowExecutionID(), "push", types.CommitSha("aabbcc"), types.GitRef("branch"), "request-id", "", ".github/workflows/main.yml", types.NilGlobalID, types.NilGlobalID)
	s.Require().NoError(err)

	_, err = s.builds.PersistError(
		ctx, s.repoID, types.NewRandomWorkflowExecutionID(), "push", types.CommitSha("ddeeff"), types.GitRef("branch"), "request-id", "", ".github/workflows/main.yml", types.NilGlobalID, types.NilGlobalID)
	s.Require().NoError(err)
}

func (s *PersistErrorTestSuite) Test_WorkflowBuildsRepository_PersistError_CreatesWorkflowBuildExecution_WriteNextGlobalID() {
	csID := types.GlobalID("MDEwOkNoZWNrU3VpdGU0MjE0NTk3NDQ=")
	csNextID := types.GlobalID("CS_kwDOAROBws4ZHvcg")

	s.mockTwirpClient.EXPECT().GetNextGlobalID(mock.Anything, s.repoID.String()).Return(s.repoNextID, nil)
	s.mockTwirpClient.EXPECT().GetNextGlobalID(mock.Anything, csID.String()).Return(csNextID, nil)
	s.mockTwirpClient.EXPECT().GetNextGlobalID(mock.Anything, ExecutingActorID.String()).Return(ExecutingActorNextID, nil)

	// Workflow build executions PersistError will fetch the next ID for triggeringActorID
	s.mockTwirpClient.EXPECT().GetNextGlobalID(mock.Anything, TriggeringActorID.String()).Return(types.NilGlobalID, nil).Once()

	ctx := context.Background()
	_, err := s.builds.PersistError(
		ctx, s.repoID, types.NewRandomWorkflowExecutionID(), "push", types.CommitSha("aabbcc"), types.GitRef("branch"), "request-id", csID, ".github/workflows/main.yml", ExecutingActorID, TriggeringActorID)
	s.Require().NoError(err)

	rows := s.conn.QueryRow(`select repository_id, repository_next_id, check_suite_id, check_suite_next_id, executing_actor_id, executing_actor_next_id from workflow_builds where check_suite_id = ?`, csNextID.String())

	var repoIDRes, repoNextIDRes, csIDRes, csNextIDRes, execActorIDRes, execActorNextIDRes types.GlobalID
	s.Require().NoError(rows.Scan(&repoIDRes, &repoNextIDRes, &csIDRes, &csNextIDRes, &execActorIDRes, &execActorNextIDRes))

	s.Require().Equal(repoIDRes, s.repoNextID)
	s.Require().Equal(csIDRes, csNextIDRes)
	s.Require().Equal(execActorIDRes, execActorNextIDRes)
}

func (s *PersistErrorTestSuite) Test_WorkflowBuildsRepository_PersistError_CreatesWorkflowBuildExecution() {
	csID := types.GlobalID("MDEwOkNoZWNrU3VpdGU4NDM3NjM5MDg=")
	csNextID := types.GlobalID("CS_kwDOEDT6U84yStDE")

	s.mockTwirpClient.EXPECT().GetNextGlobalID(mock.Anything, s.repoID.String()).Return(s.repoNextID, nil)
	s.mockTwirpClient.EXPECT().GetNextGlobalID(mock.Anything, csID.String()).Return(csNextID, nil)
	s.mockTwirpClient.EXPECT().GetNextGlobalID(mock.Anything, ExecutingActorID.String()).Return(ExecutingActorNextID, nil)

	// Workflow build executions PersistError will fetch the next ID for triggeringActorID
	s.mockTwirpClient.EXPECT().GetNextGlobalID(mock.Anything, TriggeringActorNextID.String()).Return(TriggeringActorNextID, nil).Once()

	ctx := context.Background()
	planID := types.NewRandomWorkflowExecutionID()
	_, err := s.builds.PersistError(
		ctx, s.repoID, planID, "push", types.CommitSha("aabbcc"), types.GitRef("branch"), "request-id", csID, ".github/workflows/main.yml", ExecutingActorID, TriggeringActorNextID)
	s.Require().NoError(err)

	res, err := s.executions.GetByPlanIDForTests(ctx, planID)
	s.NoError(err)

	s.Equal(planID, res.PlanID)
	s.Equal("", res.ExternalBuildID)
	s.Equal(TriggeringActorNextID, res.TriggeringActorID)
	s.Equal(1, res.Attempt)
	s.Equal(build.WorkflowStateFailed, res.State)
}
