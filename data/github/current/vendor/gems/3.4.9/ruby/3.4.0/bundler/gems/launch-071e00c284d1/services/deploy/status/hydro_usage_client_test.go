package status

import (
	"context"
	"testing"
	"time"

	"github.com/golang/protobuf/ptypes/timestamp"
	"github.com/stretchr/testify/suite"
	"google.golang.org/protobuf/types/known/timestamppb"

	"github.com/github/launch/clients/hydro/metadata"
	"github.com/github/launch/db/stores/deployer"
	"github.com/github/launch/observability/logger"
	"github.com/github/launch/types"
)

func TestHydroUsageClient(t *testing.T) {
	suite.Run(t, new(resultsUsageSuite))
}

type hydroUsageSuite struct {
	suite.Suite
	clientProvider func(hydroClient Hydro, log logs) *hydroUsageClient
	hydro          *recordingEmitter
}

var _ Hydro = (*recordingEmitter)(nil)

func (suite *hydroUsageSuite) SetupTest() {
	suite.clientProvider = newHydroUsageClient
}

func (suite *hydroUsageSuite) Test_HydroUsageClientPassesCorrectArgsToJobExecution() {
	backend := &recordingEmitter{}
	hydroUsageClient := suite.clientProvider(backend, logger.TestLogger())
	_, startedAtProto, _, completedAtProto := suite.getTimings()
	testWorkflowBuildExecutionDbID := int64(567)
	jobId := int64(666)
	checkRunId := int64(555)
	billingChecked := false
	testWorkflowRunAttempt := int64(1)

	dbData := &deployer.DataForStatusPostback{
		WorkflowBuildDatabaseID: testWorkflowBuildDbID,
		CheckSuiteState: &types.CheckSuiteState{
			RepositoryID:     testRepositoryID,
			EventSHA:         testCommitSHA,
			FlowIdentifier:   "A Workflow",
			WorkflowFilePath: testWorkflowFile,
			CheckSuiteIDPair: types.IDPair{
				GlobalID: testCheckSuiteID,
			},
		},
		CreatedAt: time.Now(),
		QueuedAt:  &testQueuedAt,
		WorkflowMetadata: metadata.WorkflowMetadata{
			Repository: &metadata.WorkflowRepositoryMetadata{
				GlobalRelayID: testRepositoryID.String(),
				ID:            3,
			},
			RepositoryOwner: &metadata.WorkflowMetadataUser{
				ID: uint32(testUserID),
			},
			InvokingUser: &metadata.WorkflowMetadataUser{
				ID: uint32(testUserID),
			},
		},
		WorkflowBuildExecutionDatabaseID: &testWorkflowBuildExecutionDbID,
		Attempt:                          &testWorkflowRunAttempt,
	}

	update := &JobStatusRequest{
		WorkflowId:  testWorkflowID,
		JobId:       testJobIDA,
		ExternalId:  testExternalID,
		DisplayName: testJobNameA,
		Number:      1,
		Runtime:     "ubuntu",
		Progress: &JobStatusRequest_Complete{
			Complete: &JobComplete{
				Result:      Result_RESULT_SUCCEEDED,
				StartedAt:   startedAtProto,
				CompletedAt: completedAtProto,
				Log: &Log{
					Url:       testJobLogsURL,
					Lines:     1,
					CreatedAt: completedAtProto,
				},
			},
		},
		Steps: []*JobStep{
			{
				ExternalId: "some-step-external-id",
				Name:       "some-step-name",
				Number:     456,
				Progress: &JobStep_Complete{
					Complete: &StepComplete{
						Result:      Result_RESULT_SUCCEEDED,
						StartedAt:   startedAtProto,
						CompletedAt: completedAtProto,
						Log: &Log{
							Url:       "http://some-step-log.log",
							Lines:     2,
							CreatedAt: completedAtProto,
						},
					},
				},
			},
		},
	}

	complete := &JobComplete{
		Result:      Result_RESULT_SUCCEEDED,
		StartedAt:   startedAtProto,
		CompletedAt: completedAtProto,
	}

	hydroUsageClient.EmitUsage(
		context.Background(),
		dbData,
		jobId,
		checkRunId,
		update,
		complete,
		billingChecked,
	)

	suite.Len(backend.jobEvents, 1, "should have emitted one job event")
	jobExecutionEvent := backend.jobEvents[0]

	suite.Equal(jobId, jobExecutionEvent.JobId, "should have passed the correct job ID")
	suite.Equal(checkRunId, jobExecutionEvent.CheckRunId, "should have passed the correct check run ID")
	suite.Equal(billingChecked, jobExecutionEvent.BillingChecked, "should have passed the correct check run ID")
}

func (s *hydroUsageSuite) getTimings() (*time.Time, *timestamp.Timestamp, *time.Time, *timestamp.Timestamp) {
	startedAt := time.Date(2000, 1, 1, 10, 0, 0, 1, time.UTC)
	startedAtProto := timestamppb.New(startedAt)

	completedAt := startedAt.Add(time.Second * 10)
	completedAtProto := timestamppb.New(completedAt)

	return &startedAt, startedAtProto, &completedAt, completedAtProto
}
