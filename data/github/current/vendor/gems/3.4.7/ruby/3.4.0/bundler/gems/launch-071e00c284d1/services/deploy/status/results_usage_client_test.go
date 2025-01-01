package status

import (
	"context"
	"time"

	"testing"

	"github.com/golang/protobuf/ptypes/timestamp"
	mock "github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/suite"
	"google.golang.org/protobuf/proto"
	"google.golang.org/protobuf/types/known/timestamppb"

	"github.com/github/launch/clients/aqueduct"
	"github.com/github/launch/clients/hydro/metadata"
	"github.com/github/launch/db/stores/deployer"
	"github.com/github/launch/observability/logger"
	"github.com/github/launch/pkg/results/entities/usage"
	"github.com/github/launch/types"
)

func TestResultsUsageClient(t *testing.T) {
	suite.Run(t, new(resultsUsageSuite))
}

type resultsUsageSuite struct {
	suite.Suite
	clientProvider func(aqueductClient aqueduct.Client, log logs) *resultsUsageClient
}

func (suite *resultsUsageSuite) SetupTest() {
	suite.clientProvider = newResultsUsageClient
}

func (suite *resultsUsageSuite) Test_EmitUsageEvent_ReturnsNil() {
	aqueductClient := aqueduct.NewMockClient(suite.T())
	resultsUsageClient := suite.clientProvider(aqueductClient, logger.TestLogger())

	_, startedAtProto, _, completedAtProto, _, queuedAtProto := suite.getTimings()
	testWorkflowBuildExecutionDbID := int64(567)
	jobId := int64(666)
	checkRunId := int64(555)
	billingChecked := false
	billingOwnerId := "E_12345"
	sampleProductSku := "linux_test"
	testWorkflowRunAttempt := int64(1)
	olderStepCompletedAtProto := timestamppb.New(completedAtProto.AsTime().Add(-10 * time.Minute))
	latestStepCompletedAtProto := timestamppb.New(completedAtProto.AsTime().Add(-2 * time.Minute))

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
				ExternalId: "another-step-external-id",
				Name:       "another-step-name",
				Number:     123,
				Progress: &JobStep_Complete{
					Complete: &StepComplete{
						Result:      Result_RESULT_SUCCEEDED,
						StartedAt:   startedAtProto,
						CompletedAt: olderStepCompletedAtProto,
						Log: &Log{
							Url:       "http://another-step-log.log",
							Lines:     2,
							CreatedAt: completedAtProto,
						},
					},
				},
			},
			{
				ExternalId: "some-step-external-id",
				Name:       "some-step-name",
				Number:     456,
				Progress: &JobStep_Complete{
					Complete: &StepComplete{
						Result:      Result_RESULT_SUCCEEDED,
						StartedAt:   startedAtProto,
						CompletedAt: latestStepCompletedAtProto,
						Log: &Log{
							Url:       "http://some-step-log.log",
							Lines:     2,
							CreatedAt: completedAtProto,
						},
					},
				},
			},
		},
		BillableOwnerId: billingOwnerId,
		QueuedAt:        queuedAtProto,
		ProductSku:      sampleProductSku,
	}

	complete := &JobComplete{
		Result:      Result_RESULT_SUCCEEDED,
		StartedAt:   startedAtProto,
		CompletedAt: completedAtProto,
	}

	jobMatcher := mock.MatchedBy(func(aj aqueduct.Job) bool {
		if aj.Queue != actionsUsageEventsQueue {
			return false
		}

		jobExec := &usage.JobExecution{}
		if err := proto.Unmarshal(aj.Payload, jobExec); err != nil {
			return false
		}

		if jobExec.LastCompletedStepAt.AsTime() != update.Steps[1].GetComplete().CompletedAt.AsTime() {
			return false
		}

		return true
	})

	aqueductClient.On("Send", mock.Anything, jobMatcher, mock.Anything, mock.Anything).Return("jobID", nil)

	jobExecutionRequest := resultsUsageClient.EmitUsage(
		context.Background(),
		dbData,
		jobId,
		checkRunId,
		update,
		complete,
		billingChecked,
	)

	suite.Nil(jobExecutionRequest)
}

func (s *resultsUsageSuite) getTimings() (*time.Time, *timestamp.Timestamp, *time.Time, *timestamp.Timestamp, *time.Time, *timestamp.Timestamp) {
	queuedAt := time.Date(2000, 1, 1, 10, 0, 0, 1, time.UTC)
	queuedAtProto := timestamppb.New(queuedAt)

	startedAt := queuedAt.Add(time.Second * 10)
	startedAtProto := timestamppb.New(queuedAt)

	completedAt := startedAt.Add(time.Second * 10)
	completedAtProto := timestamppb.New(completedAt)

	return &startedAt, startedAtProto, &completedAt, completedAtProto, &queuedAt, queuedAtProto
}
