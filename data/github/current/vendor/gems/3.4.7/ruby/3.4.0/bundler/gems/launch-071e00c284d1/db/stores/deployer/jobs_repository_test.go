package deployer

import (
	"context"
	"os"
	"strings"
	"testing"

	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/suite"

	"github.com/github/launch/clients/ghtwirp"
	"github.com/github/launch/mysqldb"
	"github.com/github/launch/observability"
	"github.com/github/launch/observability/logger"
	"github.com/github/launch/observability/statter"
	"github.com/github/launch/types"
	"github.com/github/launch/utils/asql"
	"github.com/github/launch/utils/testutils"
)

type JobsRepositorySuite struct {
	suite.Suite
	conn            *asql.SQL
	repo            *azpJobsRepository
	mockTwirpClient *ghtwirp.MockClient
}

func TestJobsRepository(t *testing.T) {
	testutils.NoShort(t)
	suite.Run(t, new(JobsRepositorySuite))
}

func (s *JobsRepositorySuite) SetupSuite() {
	conn, err := mysqldb.NewDB(statter.NullStatter(), os.Getenv("LAUNCH_DEPLOYER_TEST_DATABASE_URL"))
	s.Require().NoError(err)
	s.conn = asql.New(conn, logger.TestLogger(), statter.NullStatter(), testutils.NewNoopBreaker(), asql.LaunchCluster)
	s.mockTwirpClient = ghtwirp.NewMockClient(s.T())
	log := testutils.NewRecordingLogger()
	obs := observability.New(log.Logger, statter.NullStatter())
	globalIDMigrator := NewGlobalIDMigrator(s.mockTwirpClient)
	s.repo = &azpJobsRepository{
		db:          s.conn,
		obs:         obs,
		gidMigrator: globalIDMigrator,
	}

}

func (s *JobsRepositorySuite) SetupTest() {
	_, err := s.conn.Conn().Exec(`TRUNCATE workflow_jobs`)
	s.mockTwirpClient.On("GetNextGlobalID", mock.Anything, mock.Anything).Return(func(ctx context.Context, globalID string) types.GlobalID {
		if strings.HasPrefix(globalID, nextIDPrefix) {
			// already a next id, return original argument
			return types.GlobalID(globalID)
		}
		return nextIDFromGlobalID(types.GlobalID(globalID))
	}, nil)

	s.Require().NoError(err)
}

var workflowID string = "workflow-1234"
var jobID string = "job-1234"
var externalID string = workflowID + "," + jobID
var externalIdList = make([]string, 1)
var checkRun1 = types.GlobalID(testutils.EncodeGlobalID("CheckRun", 123))
var checkRun2 = types.GlobalID(testutils.EncodeGlobalID("CheckRun", 234))
var checkRun3 = types.GlobalID(testutils.EncodeGlobalID("CheckRun", 124))
var workflowBuildExecutionDbID = int64(1)

func (s *JobsRepositorySuite) Test_GetWorkflowJobFromJobID_NoData() {
	ctx := context.Background()

	jobs, err := s.repo.GetWorkflowJobFromJobID(ctx, workflowID, jobID)
	s.NoError(err)
	s.Nil(jobs)
}

func (s *JobsRepositorySuite) Test_GetWorkflowJobFromJobID_Works() {
	ctx := context.Background()
	dbID := int64(1)
	checkRunID := types.GlobalID("check-run-1234")
	workflowBuildExecutionDbID := int64(2)

	_, err := s.repo.CreateWorkflowJob(ctx, dbID, workflowID, jobID, checkRunID, &workflowBuildExecutionDbID)
	s.NoError(err)

	job, err := s.repo.GetWorkflowJobFromJobID(ctx, workflowID, jobID)
	s.NoError(err)
	s.NotNil(job.ID)
	s.Equal(dbID, job.WorkflowBuildID)
	s.Equal(workflowID+","+jobID, job.ExternalJobID)
	s.Equal(nextIDFromGlobalID(checkRunID), job.CheckRunID)
	s.Equal(&workflowBuildExecutionDbID, job.WorkflowBuildExecutionID)
}

func (s *JobsRepositorySuite) Test_GetWorkflowJobFromJobID_LoadsHighestCheckRunID() {
	ctx := context.Background()
	checkRun1 := types.GlobalID(testutils.EncodeGlobalID("CheckRun", 123))
	checkRun2 := types.GlobalID(testutils.EncodeGlobalID("CheckRun", 234))
	checkRun3 := types.GlobalID(testutils.EncodeGlobalID("CheckRun", 124))
	workflowBuildExecutionDbID := int64(1)

	s.mockTwirpClient.ExpectedCalls = nil
	s.mockTwirpClient.EXPECT().GetNextGlobalID(mock.Anything, checkRun1.String()).Return(types.GlobalID("CR_kwDAew"), nil)
	s.mockTwirpClient.EXPECT().GetNextGlobalID(mock.Anything, checkRun2.String()).Return(types.GlobalID("CR_kwDAzOo"), nil)
	s.mockTwirpClient.EXPECT().GetNextGlobalID(mock.Anything, checkRun3.String()).Return(types.GlobalID("CR_kwDAfA"), nil)

	// Create them in order so by default sorting we get the first one on fetch
	_, err := s.repo.CreateWorkflowJob(ctx, 1, workflowID, jobID, checkRun1, &workflowBuildExecutionDbID)
	s.NoError(err)
	_, err = s.repo.CreateWorkflowJob(ctx, 1, workflowID, jobID, checkRun2, &workflowBuildExecutionDbID)
	s.NoError(err)
	_, err = s.repo.CreateWorkflowJob(ctx, 1, workflowID, jobID, checkRun3, &workflowBuildExecutionDbID)
	s.NoError(err)

	job, err := s.repo.GetWorkflowJobFromJobID(ctx, workflowID, jobID)
	s.NoError(err)

	// Ensure we get back the second check run as it has the highest ID
	s.Equal(types.GlobalID("CR_kwDAzOo"), job.CheckRunID)
	s.mockTwirpClient.ExpectedCalls = nil
}

func (s *JobsRepositorySuite) Test_GetWorkflowJobID_NoDatabaseID() {
	ctx := context.Background()
	dbID := int64(1)
	checkRunID := types.GlobalID("check-run-1234")

	_, err := s.repo.CreateWorkflowJob(ctx, dbID, workflowID, jobID, checkRunID, nil)
	s.NoError(err)

	job, err := s.repo.GetWorkflowJobFromJobID(ctx, workflowID, jobID)
	s.NoError(err)
	s.Nil(job.WorkflowBuildExecutionID)
}

func (s *JobsRepositorySuite) Test_UpdateBillingChecked() {
	ctx := context.Background()
	dbID := int64(1)
	checkRunID := types.GlobalID("check-run-1234")

	_, err := s.repo.CreateWorkflowJob(ctx, dbID, workflowID, jobID, checkRunID, nil)
	s.NoError(err)

	job, err := s.repo.GetWorkflowJobFromJobID(ctx, workflowID, jobID)
	s.Equal(job.BillingChecked, true)

	err = s.repo.UpdateBillingChecked(ctx, workflowID, jobID, false)
	s.NoError(err)

	job, err = s.repo.GetWorkflowJobFromJobID(ctx, workflowID, jobID)
	s.Equal(job.BillingChecked, false)
}

// GetWorkflowJobsfromJobIDs will return a slice of WorkflowJobs ids mapped to their latest CheckRunID representing the records for the given list of JobIDs.

func (s *JobsRepositorySuite) Test_GetWorkflowJobsFromJobIDs_NoData() {
	ctx := context.Background()
	jobs, err := s.repo.GetWorkflowJobsFromJobIds(ctx, externalIdList)
	s.NoError(err)
	s.Equal(0, len(jobs))
}

func (s *JobsRepositorySuite) Test_GetWorkflowJobsFromJobIDs_Works() {
	ctx := context.Background()

	_, errfirst := s.repo.CreateWorkflowJob(ctx, workflowBuildExecutionDbID, workflowID, jobID, checkRun1, &workflowBuildExecutionDbID)
	s.NoError(errfirst)

	externalIdList[0] = externalID
	jobs, err := s.repo.GetWorkflowJobsFromJobIds(ctx, externalIdList)

	s.NoError(err)
	s.NotNil(jobs)
	s.Equal(string(nextIDFromGlobalID(checkRun1)), jobs["workflow-1234,job-1234"])
}

func (s *JobsRepositorySuite) Test_GetWorkflowJobsFromJobIDs_LoadsLatestCheckRun() {
	ctx := context.Background()
	externalIdList[0] = externalID

	// Create them in order so by default sorting we get the first one on fetch
	_, err := s.repo.CreateWorkflowJob(ctx, 1, workflowID, jobID, checkRun1, &workflowBuildExecutionDbID)
	s.NoError(err)
	_, err = s.repo.CreateWorkflowJob(ctx, 1, workflowID, jobID, checkRun2, &workflowBuildExecutionDbID)
	s.NoError(err)
	_, err = s.repo.CreateWorkflowJob(ctx, 1, workflowID, jobID, checkRun3, &workflowBuildExecutionDbID)
	s.NoError(err)

	jobs, err := s.repo.GetWorkflowJobsFromJobIds(ctx, externalIdList)
	s.NoError(err)

	// Ensure we get back the second check run as it has the highest ID
	s.Equal(string(nextIDFromGlobalID(checkRun3)), jobs[workflowID+","+jobID])
}

func (s *JobsRepositorySuite) Test_GetWorkflowJobsFromJobIDs_NoDatabaseID() {
	ctx := context.Background()
	externalIdList[0] = externalID

	_, err := s.repo.CreateWorkflowJob(ctx, workflowBuildExecutionDbID, externalID, jobID, checkRun1, nil)
	s.NoError(err)

	jobs, err := s.repo.GetWorkflowJobsFromJobIds(ctx, externalIdList)
	s.NoError(err)
	s.Equal("", jobs[workflowID+","+jobID])
}
