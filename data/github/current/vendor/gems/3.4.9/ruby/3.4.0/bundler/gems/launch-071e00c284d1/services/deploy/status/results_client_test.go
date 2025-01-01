package status

import (
	"context"
	"testing"
	"time"

	"github.com/golang/protobuf/ptypes/timestamp"
	mock "github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/suite"
	"google.golang.org/protobuf/types/known/timestamppb"
	"google.golang.org/protobuf/types/known/wrapperspb"

	"github.com/github/launch/clients/aqueduct"

	"github.com/github/launch/observability/logger"
	"github.com/github/launch/pkg/results/entities/actions"
	"github.com/github/launch/pkg/results/entities/checks"
	"github.com/github/launch/types"
	"github.com/github/launch/utils/testutils"
)

func TestResultsStatusClient(t *testing.T) {
	suite.Run(t, new(resultsStatusServiceSuite))
}

var (
	checkRunID      = types.GlobalID(testutils.EncodeGlobalID("CheckRun", 3047))
	invalidGlobalID = types.GlobalID("invalidGlobalID")
)

type resultsStatusServiceSuite struct {
	suite.Suite
	clientProvider func(aqueductClient aqueduct.Client, log logs) *resultsStatusClient
}

func (suite *resultsStatusServiceSuite) SetupTest() {
	suite.clientProvider = newResultsStatusClient
}

func (suite *resultsStatusServiceSuite) Test_UpdateGateStatus_ReturnsNil() {
	aqueductClient := aqueduct.NewMockClient(suite.T())
	resultsStatusClient := suite.clientProvider(aqueductClient, logger.TestLogger())
	aqueductClient.On("Send", mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return("jobID", nil)

	gateStatusUpdateRequest := resultsStatusClient.UpdateGateStatus(context.Background(), &GateStatusRequest{
		ExternalId:  "test,externalId",
		GateId:      testGateID.String(),
		IsOpen:      true,
		Deadline:    timestamppb.Now(),
		Token:       "testToken",
		IsConcluded: false,
	}, UpdateGateStatusParams{
		RepositoryID: testRepositoryID,
		CheckRunID:   checkRunID,
	})

	suite.Nil(gateStatusUpdateRequest)
}

func (suite *resultsStatusServiceSuite) Test_UpdateCheckSuite_ReturnsNil() {
	aqueductClient := aqueduct.NewMockClient(suite.T())
	resultsStatusClient := suite.clientProvider(aqueductClient, logger.TestLogger())
	aqueductClient.On("Send", mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return("jobID", nil)

	updateCheckSuiteRequest := resultsStatusClient.UpdateCheckSuite(context.Background(), &RunStatusRequest{
		WorkflowId: testWorkflowID,
		Progress: &RunStatusRequest_Complete{
			Complete: &RunComplete{
				StartedAt:   timestamppb.Now(),
				CompletedAt: timestamppb.Now(),
				Conclusion:  RunConclusion_SUCCEEDED,
				ExpiresAt:   timestamppb.Now(),
			},
		},
		CompletedLog: &Log{
			Url:       "testURL",
			Lines:     1,
			CreatedAt: timestamppb.Now(),
		},
		Artifacts:   []*Artifact{},
		Annotations: []*Annotation{},
		Concurrency: &Concurrency{
			Group: "testGroup",
			WaitingOnResource: &WaitingOnResource{
				RunExternalId: "testRunExternalId",
				JobExternalId: "testJobExternalId",
				Identifier:    "testIdentifier",
			},
		},
	}, UpdateCheckSuiteParams{
		CheckSuiteState: &types.CheckSuiteState{
			RepositoryID:     testRepositoryID,
			CheckSuiteIDPair: testCheckSuiteIDPair,
		},
		WaitingOn: &WaitingOn{
			CheckSuiteID: testCheckSuiteID,
			CheckRunID:   checkRunID,
		},
	})

	suite.Nil(updateCheckSuiteRequest)
}

func (suite *resultsStatusServiceSuite) Test_UpdateCheckRun_ReturnsNil() {
	aqueductClient := aqueduct.NewMockClient(suite.T())
	resultsStatusClient := suite.clientProvider(aqueductClient, logger.TestLogger())
	aqueductClient.On("Send", mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return("jobID", nil)

	updateCheckRunRequest := resultsStatusClient.UpdateCheckRun(context.Background(), &JobStatusRequest{
		WorkflowId:  "testWorkflowId",
		JobId:       "testJobId",
		ExternalId:  "testExternalId",
		Number:      1,
		DisplayName: "testDisplayName",
		Artifacts:   []*Artifact{},
		Annotations: []*Annotation{},
		Steps:       []*JobStep{},
		Progress: &JobStatusRequest_Complete{
			Complete: &JobComplete{
				StartedAt:   timestamppb.Now(),
				CompletedAt: timestamppb.Now(),
				Result:      Result_RESULT_SUCCEEDED,
			},
		},
		JobKey:         "testJobKey",
		Runtime:        "testRuntime",
		RuntimeVersion: "testRuntimeVersion",
		SelfHosted:     false,
		DurationMs:     1,
		Delayed:        false,
		Environment: &Environment{
			Name: "testEnvironmentName",
			Url:  "testEnvironmentURL",
		},
		ParentJobId: "testParentJobId",
		Concurrency: &Concurrency{
			Group: "testGroup",
			WaitingOnResource: &WaitingOnResource{
				RunExternalId: "testRunExternalId",
				JobExternalId: "testJobExternalId",
				Identifier:    "testIdentifier",
			},
		},
		RunnerId:                1,
		RunnerName:              "testRunnerName",
		RunnerGroupId:           1,
		RunnerGroupName:         "testRunnerGroupName",
		IsClonedFromPreviousRun: false,
		RunnerProperties:        "testRunnerProperties",
		RunnerType:              "testRunnerType",
	}, UpdateCheckRunParams{
		CheckSuiteState: &types.CheckSuiteState{
			RepositoryID:     testRepositoryID,
			CheckSuiteIDPair: testCheckSuiteIDPair,
		},
		CheckRunID: checkRunID,
		WaitingOn: &WaitingOn{
			CheckSuiteID: testCheckSuiteID,
			CheckRunID:   checkRunID,
		},
	})

	suite.Nil(updateCheckRunRequest)
}

func (suite *resultsStatusServiceSuite) Test_getWorkflowRunGUIDFromExternalID_validExternalID_ReturnsID() {
	testExternalID := "test,ExternalID"

	workflowRunGUID := getWorkflowRunGUIDFromExternalID(testExternalID)

	suite.Assert().Equal("test", workflowRunGUID)
}

func (suite *resultsStatusServiceSuite) Test_getWorkflowRunGUIDFromExternalID_externalIDNoCommas_ReturnsID() {
	testExternalID := "test"

	workflowRunGUID := getWorkflowRunGUIDFromExternalID(testExternalID)

	suite.Assert().Equal("test", workflowRunGUID)
}

func (suite *resultsStatusServiceSuite) Test_getRepositoryID_validGlobalID_ReturnsID() {
	integerID := int64(1)
	repositoryGlobalID := types.GlobalID(testutils.EncodeGlobalID("Repository", integerID))

	repositoryID, err := getRepositoryID(repositoryGlobalID)

	suite.Assert().Nil(err)
	suite.Assert().Equal(repositoryID, integerID)
}

func (suite *resultsStatusServiceSuite) Test_getRepositoryID_invalidGlobalID_ReturnsError() {
	repositoryID, err := getRepositoryID(invalidGlobalID)

	suite.Assert().Equal("failed to decode Repository GlobalID: (Legacy) Invalid base64-encoding", err.Error())
	suite.Assert().Equal(repositoryID, int64(0))
}

func (suite *resultsStatusServiceSuite) Test_getRepositoryID_validGlobalIDNotRepository_ReturnsError() {
	integerID := int64(1)
	checkSuiteGlobalID := types.GlobalID(testutils.EncodeGlobalID("CheckSuite", integerID))

	repositoryID, err := getRepositoryID(checkSuiteGlobalID)

	suite.Assert().Equal("Unexpected global id type CheckSuite, expected Repository", err.Error())
	suite.Assert().Equal(repositoryID, int64(0))
}

func (suite *resultsStatusServiceSuite) Test_getGateID_validGlobalID_ReturnsID() {
	integerID := int64(1)
	gateGlobalID := types.GlobalID(testutils.EncodeGlobalID("Gate", integerID))

	gateID, err := getGateID(gateGlobalID.String())

	suite.Assert().Nil(err)
	suite.Assert().Equal(gateID, integerID)
}

func (suite *resultsStatusServiceSuite) Test_getGateID_invalidGlobalID_ReturnsError() {
	gateID, err := getGateID(invalidGlobalID.String())

	suite.Assert().Equal("failed to decode Gate GlobalID: (Legacy) Invalid base64-encoding", err.Error())
	suite.Assert().Equal(gateID, int64(0))
}

func (suite *resultsStatusServiceSuite) Test_getGateID_validGlobalIDNotRepository_ReturnsError() {
	integerID := int64(1)
	checkSuiteGlobalID := types.GlobalID(testutils.EncodeGlobalID("CheckSuite", integerID))

	gateID, err := getGateID(checkSuiteGlobalID.String())

	suite.Assert().Equal("Unexpected global id type CheckSuite, expected Gate", err.Error())
	suite.Assert().Equal(gateID, int64(0))
}

func (suite *resultsStatusServiceSuite) Test_getCheckSuiteID_validGlobalID_ReturnsID() {
	integerID := int64(1)
	checkSuiteGlobalID := types.GlobalID(testutils.EncodeGlobalID("CheckSuite", integerID))

	checkSuiteID, err := getCheckSuiteID(checkSuiteGlobalID)

	suite.Assert().Nil(err)
	suite.Assert().Equal(checkSuiteID, integerID)
}

func (suite *resultsStatusServiceSuite) Test_getCheckSuiteID_invalidGlobalID_ReturnsError() {
	repositoryID, err := getCheckSuiteID(invalidGlobalID)

	suite.Assert().Equal("failed to decode Check Suite GlobalID: (Legacy) Invalid base64-encoding", err.Error())
	suite.Assert().Equal(repositoryID, int64(0))
}

func (suite *resultsStatusServiceSuite) Test_getCheckSuiteID_validGlobalIDNotCheckSuite_ReturnsError() {
	integerID := int64(1)
	repositoryGlobalID := types.GlobalID(testutils.EncodeGlobalID("Repository", integerID))

	checkSuiteID, err := getCheckSuiteID(repositoryGlobalID)

	suite.Assert().Equal("Unexpected global id type Repository, expected CheckSuite", err.Error())
	suite.Assert().Equal(checkSuiteID, int64(0))
}

func (suite *resultsStatusServiceSuite) Test_getCheckRunID_validGlobalID_ReturnsID() {
	integerID := int64(1)
	checkRunGlobalID := types.GlobalID(testutils.EncodeGlobalID("CheckRun", integerID))

	checkRunID, err := getCheckRunID(checkRunGlobalID)

	suite.Assert().Nil(err)
	suite.Assert().Equal(checkRunID, integerID)
}

func (suite *resultsStatusServiceSuite) Test_getCheckRunID_invalidGlobalID_ReturnsError() {
	repositoryID, err := getCheckRunID(invalidGlobalID)

	suite.Assert().Equal("failed to decode Check Run GlobalID: (Legacy) Invalid base64-encoding", err.Error())
	suite.Assert().Equal(repositoryID, int64(0))
}

func (suite *resultsStatusServiceSuite) Test_getCheckRunID_validGlobalIDNotCheckSuite_ReturnsError() {
	integerID := int64(1)
	repositoryGlobalID := types.GlobalID(testutils.EncodeGlobalID("Repository", integerID))

	checkRunID, err := getCheckRunID(repositoryGlobalID)

	suite.Assert().Equal("Unexpected global id type Repository, expected CheckRun", err.Error())
	suite.Assert().Equal(checkRunID, int64(0))
}

func (suite *resultsStatusServiceSuite) Test_getGateStatusResults_Open_ReturnsStatusOpen() {
	isOpen := true

	status := getGateStatusResults(isOpen)

	suite.Assert().Equal(actions.GateRequestState_STATE_OPEN, status)
}

func (suite *resultsStatusServiceSuite) Test_getGateStatusResults_Closed_ReturnsStatusClosed() {
	isOpen := false

	status := getGateStatusResults(isOpen)

	suite.Assert().Equal(actions.GateRequestState_STATE_CLOSED, status)
}

func (suite *resultsStatusServiceSuite) Test_getCheckSuiteStatus_Complete_ReturnsStatusComplete() {
	runStatusRequest := &RunStatusRequest{
		WorkflowId: testWorkflowID,
		Progress: &RunStatusRequest_Complete{
			Complete: &RunComplete{
				StartedAt:   timestamppb.Now(),
				CompletedAt: timestamppb.Now(),
				Conclusion:  RunConclusion_SUCCEEDED,
				ExpiresAt:   timestamppb.Now(),
			},
		},
	}

	status := getCheckSuiteStatus(runStatusRequest)

	suite.Assert().Equal(checks.CheckStatus_STATUS_COMPLETED, status)
}

func (suite *resultsStatusServiceSuite) Test_getCheckSuiteStatus_InProgress_ReturnsStatusPending() {
	runStatusRequest := &RunStatusRequest{
		WorkflowId: testWorkflowID,
		Progress:   &RunStatusRequest_NotStarted{},
	}

	status := getCheckSuiteStatus(runStatusRequest)

	suite.Assert().Equal(checks.CheckStatus_STATUS_PENDING, status)
}

func (suite *resultsStatusServiceSuite) Test_getCheckRunStatus_Complete_ReturnsStatusComplete() {
	jobStatusRequest := &JobStatusRequest{
		WorkflowId: testWorkflowID,
		Progress:   &JobStatusRequest_Complete{},
	}

	status := getCheckRunStatus(jobStatusRequest)

	suite.Assert().Equal(checks.CheckStatus_STATUS_COMPLETED, status)
}

func (suite *resultsStatusServiceSuite) Test_getCheckRunStatus_InProgress_ReturnsStatusInProgress() {
	jobStatusRequest := &JobStatusRequest{
		WorkflowId: testWorkflowID,
		Progress: &JobStatusRequest_InProgress{
			InProgress: &JobInProgress{
				Status: Status_STATUS_IN_PROGRESS,
			},
		},
	}

	status := getCheckRunStatus(jobStatusRequest)

	suite.Assert().Equal(checks.CheckStatus_STATUS_IN_PROGRESS, status)
}

func (suite *resultsStatusServiceSuite) Test_getCheckSuiteConclusion_Succeeded_ReturnsConclusionSucceeded() {
	runStatusRequest := &RunStatusRequest{
		WorkflowId: testWorkflowID,
		Progress: &RunStatusRequest_Complete{
			Complete: &RunComplete{
				StartedAt:   timestamppb.Now(),
				CompletedAt: timestamppb.Now(),
				Conclusion:  RunConclusion_SUCCEEDED,
				ExpiresAt:   timestamppb.Now(),
			},
		},
	}

	conclusion := getCheckSuiteConclusion(runStatusRequest)

	suite.Assert().Equal(checks.CheckConclusion_CONCLUSION_SUCCESS, conclusion)
}

func (suite *resultsStatusServiceSuite) Test_getCheckSuiteConclusion_Cancelled_ReturnsConclusionCancelled() {
	runStatusRequest := &RunStatusRequest{
		WorkflowId: testWorkflowID,
		Progress: &RunStatusRequest_Complete{
			Complete: &RunComplete{
				StartedAt:   timestamppb.Now(),
				CompletedAt: timestamppb.Now(),
				Conclusion:  RunConclusion_CANCELED,
				ExpiresAt:   timestamppb.Now(),
			},
		},
	}

	conclusion := getCheckSuiteConclusion(runStatusRequest)

	suite.Assert().Equal(checks.CheckConclusion_CONCLUSION_CANCELLED, conclusion)
}

func (suite *resultsStatusServiceSuite) Test_getCheckSuiteConclusion_Failed_ReturnsConclusionFailure() {
	runStatusRequest := &RunStatusRequest{
		WorkflowId: testWorkflowID,
		Progress: &RunStatusRequest_Complete{
			Complete: &RunComplete{
				StartedAt:   timestamppb.Now(),
				CompletedAt: timestamppb.Now(),
				Conclusion:  RunConclusion_FAILED,
				ExpiresAt:   timestamppb.Now(),
			},
		},
	}

	conclusion := getCheckSuiteConclusion(runStatusRequest)

	suite.Assert().Equal(checks.CheckConclusion_CONCLUSION_FAILURE, conclusion)
}

func (suite *resultsStatusServiceSuite) Test_getCheckSuiteConclusion_Skipped_ReturnsConclusionSkipped() {
	runStatusRequest := &RunStatusRequest{
		WorkflowId: testWorkflowID,
		Progress: &RunStatusRequest_Complete{
			Complete: &RunComplete{
				StartedAt:   timestamppb.Now(),
				CompletedAt: timestamppb.Now(),
				Conclusion:  RunConclusion_SKIPPED,
				ExpiresAt:   timestamppb.Now(),
			},
		},
	}

	conclusion := getCheckSuiteConclusion(runStatusRequest)

	suite.Assert().Equal(checks.CheckConclusion_CONCLUSION_SKIPPED, conclusion)
}

func (suite *resultsStatusServiceSuite) Test_getCheckSuiteConclusion_NotProvided_ReturnsConclusionUnknown() {
	runStatusRequest := &RunStatusRequest{
		WorkflowId: testWorkflowID,
		Progress: &RunStatusRequest_Complete{
			Complete: &RunComplete{
				StartedAt:   timestamppb.Now(),
				CompletedAt: timestamppb.Now(),
				Conclusion:  RunConclusion_NOT_PROVIDED,
				ExpiresAt:   timestamppb.Now(),
			},
		},
	}

	conclusion := getCheckSuiteConclusion(runStatusRequest)

	suite.Assert().Equal(checks.CheckConclusion_CONCLUSION_UNKNOWN, conclusion)
}

func (suite *resultsStatusServiceSuite) Test_getCheckSuiteConclusion_Unknown_ReturnsError() {
	runStatusRequest := &RunStatusRequest{
		WorkflowId: testWorkflowID,
		Progress: &RunStatusRequest_Complete{
			Complete: &RunComplete{
				StartedAt:   timestamppb.Now(),
				CompletedAt: timestamppb.Now(),
				Conclusion:  100,
				ExpiresAt:   timestamppb.Now(),
			},
		},
	}

	conclusion := getCheckSuiteConclusion(runStatusRequest)

	suite.Assert().Equal(checks.CheckConclusion_CONCLUSION_UNKNOWN, conclusion)
}

func (suite *resultsStatusServiceSuite) Test_getCheckRunConclusion_Succeeded_ReturnsConclusionSucceeded() {
	jobStatusRequest := &JobStatusRequest{
		WorkflowId: testWorkflowID,
		Progress: &JobStatusRequest_Complete{
			Complete: &JobComplete{
				StartedAt:   timestamppb.Now(),
				CompletedAt: timestamppb.Now(),
				Result:      Result_RESULT_SUCCEEDED,
			},
		},
	}

	conclusion := getCheckRunConclusion(jobStatusRequest)

	suite.Assert().Equal(checks.CheckConclusion_CONCLUSION_SUCCESS, conclusion)
}

func (suite *resultsStatusServiceSuite) Test_getCheckRunConclusion_Failed_ReturnsConclusionFailed() {
	jobStatusRequest := &JobStatusRequest{
		WorkflowId: testWorkflowID,
		Progress: &JobStatusRequest_Complete{
			Complete: &JobComplete{
				StartedAt:   timestamppb.Now(),
				CompletedAt: timestamppb.Now(),
				Result:      Result_RESULT_FAILED,
			},
		},
	}

	conclusion := getCheckRunConclusion(jobStatusRequest)

	suite.Assert().Equal(checks.CheckConclusion_CONCLUSION_FAILURE, conclusion)
}

func (suite *resultsStatusServiceSuite) Test_getCheckAnnotations_ValidAnnotations_ReturnsValidAnnotations() {
	testAnnotations := []*Annotation{
		{
			AnnotationLevel: 1,
			Message:         "testMessage",
			RawDetails:      "testDetails",
			Path:            "testPath",
			StartLine:       2,
			EndLine:         3,
			StartColumn:     4,
			EndColumn:       5,
			Title:           "testTitle",
			StepNumber:      6,
		},
	}

	checkAnnotations := getCheckAnnotations(testAnnotations)
	firstAnnotation := checkAnnotations[0]

	suite.Assert().Equal(len(checkAnnotations), 1)
	suite.Assert().Equal(firstAnnotation.AnnotationLevel, checks.CheckAnnotation_LEVEL_NOTICE)
	suite.Assert().Equal(firstAnnotation.Message, "testMessage")
	suite.Assert().Equal(firstAnnotation.RawDetails, wrapperspb.String("testDetails"))
	suite.Assert().Equal(firstAnnotation.Path, wrapperspb.String("testPath"))
	suite.Assert().Equal(firstAnnotation.StartLine, wrapperspb.Int64(2))
	suite.Assert().Equal(firstAnnotation.EndLine, wrapperspb.Int64(3))
	suite.Assert().Equal(firstAnnotation.StartColumn, wrapperspb.Int64(4))
	suite.Assert().Equal(firstAnnotation.EndColumn, wrapperspb.Int64(5))
	suite.Assert().Equal(firstAnnotation.Title, wrapperspb.String("testTitle"))
	suite.Assert().Equal(firstAnnotation.StepNumber, wrapperspb.Int64(6))
}

func (suite *resultsStatusServiceSuite) Test_getCompletedLogURL_ValidLog_ReturnsValidLogURL() {
	testLog := &Log{
		Url:       "testURL",
		Lines:     100,
		CreatedAt: &timestamp.Timestamp{},
	}

	completedLogURL := getCompletedLogURL(testLog)

	suite.Assert().Equal(completedLogURL, wrapperspb.String("testURL"))
}

func (suite *resultsStatusServiceSuite) Test_getArtifacts_ValidArtifacts_ReturnsValidActionsArtifacts() {
	testArtifacts := []*Artifact{
		{
			Name:      "testName",
			Url:       "testURL",
			CreatedAt: &timestamp.Timestamp{},
			ExpiresAt: &timestamp.Timestamp{},
			Size:      42,
		},
	}

	artifacts := getArtifacts(testArtifacts)
	firstArtifact := artifacts[0]

	suite.Assert().Equal(len(artifacts), 1)
	suite.Assert().Equal(firstArtifact.Name, "testName")
	suite.Assert().Equal(firstArtifact.Size, int64(42))
	suite.Assert().Equal(firstArtifact.SourceUrl, "testURL")
	suite.Assert().Equal(firstArtifact.CreatedAt, &timestamp.Timestamp{})
	suite.Assert().Equal(firstArtifact.ExpiresAt, &timestamp.Timestamp{})
}

func (suite *resultsStatusServiceSuite) Test_getArtifact_ValidArtifact_ReturnsValidActionsArtifact() {
	testArtifact := &Artifact{
		Name:      "testName",
		Url:       "testURL",
		CreatedAt: &timestamp.Timestamp{},
		ExpiresAt: &timestamp.Timestamp{},
		Size:      42,
	}

	artifact := getArtifact(testArtifact)

	suite.Assert().Equal(artifact.Name, "testName")
	suite.Assert().Equal(artifact.Size, int64(42))
	suite.Assert().Equal(artifact.SourceUrl, "testURL")
	suite.Assert().Equal(artifact.CreatedAt, &timestamp.Timestamp{})
	suite.Assert().Equal(artifact.ExpiresAt, &timestamp.Timestamp{})
}

func (suite *resultsStatusServiceSuite) Test_getArtifact_ValidArtifactNoExpiresAt_ReturnsValidActionsArtifact() {
	testArtifact := &Artifact{
		Name:      "testName",
		Url:       "testURL",
		CreatedAt: &timestamp.Timestamp{},
		ExpiresAt: nil,
		Size:      42,
	}

	artifact := getArtifact(testArtifact)
	var nilTime *timestamppb.Timestamp

	suite.Assert().Equal(artifact.Name, "testName")
	suite.Assert().Equal(artifact.Size, int64(42))
	suite.Assert().Equal(artifact.SourceUrl, "testURL")
	suite.Assert().Equal(artifact.CreatedAt, &timestamp.Timestamp{})
	suite.Assert().Equal(artifact.ExpiresAt, nilTime)
}

func (suite *resultsStatusServiceSuite) Test_getConcurrency_ValidCheckSuiteInput_ReturnsValidActionsConcurrency() {
	testConcurrency := &Concurrency{
		Group: "testGroup",
		WaitingOnResource: &WaitingOnResource{
			RunExternalId: "testRunExternalId",
			JobExternalId: "testJobExternalId",
			Identifier:    "testIdentifier",
		},
	}

	testWaitingOn := &WaitingOn{
		CheckSuiteID: testCheckSuiteID,
	}

	concurrency, err := getConcurrency(testConcurrency, testWaitingOn)

	suite.Assert().Nil(err)
	suite.Assert().Equal(concurrency.Group, "testGroup")
	suite.Assert().Equal(concurrency.WaitingOn, &actions.Concurrency_CheckSuiteId{CheckSuiteId: 1})
}

func (suite *resultsStatusServiceSuite) Test_getConcurrency_ValidCheckRunInput_ReturnsValidActionsConcurrency() {
	testConcurrency := &Concurrency{
		Group: "testGroup",
		WaitingOnResource: &WaitingOnResource{
			RunExternalId: "testRunExternalId",
			JobExternalId: "testJobExternalId",
			Identifier:    "testIdentifier",
		},
	}

	testWaitingOn := &WaitingOn{
		CheckRunID: checkRunID,
	}

	concurrency, err := getConcurrency(testConcurrency, testWaitingOn)

	suite.Assert().Nil(err)
	suite.Assert().Equal(concurrency.Group, "testGroup")
	suite.Assert().Equal(concurrency.WaitingOn, &actions.Concurrency_CheckRunId{CheckRunId: 3047})
}

func (suite *resultsStatusServiceSuite) Test_getConcurrency_ValidEmptyWaitingOnInput_ReturnsValidActionsConcurrency() {
	testConcurrency := &Concurrency{
		Group: "testGroup",
		WaitingOnResource: &WaitingOnResource{
			RunExternalId: "testRunExternalId",
			JobExternalId: "testJobExternalId",
			Identifier:    "testIdentifier",
		},
	}

	testWaitingOn := &WaitingOn{}

	concurrency, err := getConcurrency(testConcurrency, testWaitingOn)

	suite.Assert().Nil(err)
	suite.Assert().Equal(concurrency.Group, "testGroup")
	suite.Assert().Nil(concurrency.WaitingOn)
}

func (suite *resultsStatusServiceSuite) Test_getConcurrency_InvalidCheckSuiteID_ReturnsError() {
	testConcurrency := &Concurrency{
		Group: "testGroup",
		WaitingOnResource: &WaitingOnResource{
			RunExternalId: "testRunExternalId",
			JobExternalId: "testJobExternalId",
			Identifier:    "testIdentifier",
		},
	}
	testWaitingOn := &WaitingOn{
		CheckSuiteID: invalidGlobalID,
		CheckRunID:   checkRunID,
	}

	concurrency, err := getConcurrency(testConcurrency, testWaitingOn)

	suite.Assert().Equal("failed to get check suite ID: failed to decode Check Suite GlobalID: (Legacy) Invalid base64-encoding", err.Error())
	suite.Assert().Nil(concurrency)
}

func (suite *resultsStatusServiceSuite) Test_getConcurrency_InvalidCheckRunID_ReturnsError() {
	testConcurrency := &Concurrency{
		Group: "testGroup",
		WaitingOnResource: &WaitingOnResource{
			RunExternalId: "testRunExternalId",
			JobExternalId: "testJobExternalId",
			Identifier:    "testIdentifier",
		},
	}
	testWaitingOn := &WaitingOn{
		CheckSuiteID: testCheckSuiteID,
		CheckRunID:   invalidGlobalID,
	}

	concurrency, err := getConcurrency(testConcurrency, testWaitingOn)

	suite.Assert().Equal("failed to get check run ID: failed to decode Check Run GlobalID: (Legacy) Invalid base64-encoding", err.Error())
	suite.Assert().Nil(concurrency)
}

func (suite *resultsStatusServiceSuite) Test_getStepsResults_ValidJobSteps_ReturnsValidSteps() {
	time := timestamppb.Now()
	testJobSteps := []*JobStep{
		{
			ExternalId: "testExternalId",
			Number:     42,
			Name:       "testJobStepName",
			Progress: &JobStep_InProgress{
				InProgress: &StepInProgress{
					Status:    Status_STATUS_IN_PROGRESS,
					StartedAt: time,
				},
			},
		},
	}

	steps, err := getStepsResults(testJobSteps)
	firstStep := steps[0]

	suite.Assert().Nil(err)
	suite.Assert().Equal(len(steps), 1)
	suite.Assert().Equal(firstStep.ExternalId, "testExternalId")
	suite.Assert().Equal(firstStep.Number, int64(42))
	suite.Assert().Equal(firstStep.Name, "testJobStepName")
	suite.Assert().Equal(firstStep.StartedAt, time)
	suite.Assert().Equal(firstStep.Status, checks.CheckStatus_STATUS_IN_PROGRESS)
}

func (suite *resultsStatusServiceSuite) Test_getStepResults_ValidJobStepInProgress_ReturnsValidStep() {
	time := timestamppb.Now()
	testJobStep := &JobStep{
		ExternalId: "testExternalId",
		Number:     42,
		Name:       "testJobStepName",
		Progress: &JobStep_InProgress{
			InProgress: &StepInProgress{
				Status:    Status_STATUS_IN_PROGRESS,
				StartedAt: time,
			},
		},
	}

	step, err := getStepResults(testJobStep)

	suite.Assert().Nil(err)
	suite.Assert().Equal(step.ExternalId, "testExternalId")
	suite.Assert().Equal(step.Number, int64(42))
	suite.Assert().Equal(step.Name, "testJobStepName")
	suite.Assert().Equal(step.StartedAt, time)
	suite.Assert().Equal(step.Status, checks.CheckStatus_STATUS_IN_PROGRESS)
}

func (suite *resultsStatusServiceSuite) Test_getStepResults_ValidJobStepComplete_ReturnsValidStep() {
	time := timestamppb.Now()
	testJobStep := &JobStep{
		ExternalId: "testExternalId",
		Number:     42,
		Name:       "testJobStepName",
		Progress: &JobStep_Complete{
			Complete: &StepComplete{
				StartedAt:   time,
				CompletedAt: time,
				Result:      Result_RESULT_SUCCEEDED,
				Log: &Log{
					Url:   "testLogURL",
					Lines: 12,
				},
			},
		},
	}

	step, err := getStepResults(testJobStep)

	suite.Assert().Nil(err)
	suite.Assert().Equal(step.ExternalId, "testExternalId")
	suite.Assert().Equal(step.Number, int64(42))
	suite.Assert().Equal(step.Name, "testJobStepName")
	suite.Assert().Equal(step.StartedAt, time)
	suite.Assert().Equal(step.CompletedAt, time)
	suite.Assert().Equal(step.Status, checks.CheckStatus_STATUS_COMPLETED)
	suite.Assert().Equal(step.Conclusion, checks.CheckConclusion_CONCLUSION_SUCCESS)
	suite.Assert().Equal(step.CompletedLogUrl, wrapperspb.String("testLogURL"))
	suite.Assert().Equal(step.CompletedLogLines, wrapperspb.Int64(12))
}

func (suite *resultsStatusServiceSuite) Test_getStepResults_MissingStepLogs_DoesNotPanic() {
	time := timestamppb.Now()
	testJobStep := &JobStep{
		ExternalId: "testExternalId",
		Number:     42,
		Name:       "testJobStepName",
		Progress: &JobStep_Complete{
			Complete: &StepComplete{
				StartedAt:   time,
				CompletedAt: time,
				Result:      Result_RESULT_SUCCEEDED,
				Log:         nil,
			},
		},
	}

	step, err := getStepResults(testJobStep)

	suite.Assert().Nil(err)
	suite.Assert().Equal(step.ExternalId, "testExternalId")
	suite.Assert().Equal(step.Number, int64(42))
	suite.Assert().Equal(step.Name, "testJobStepName")
	suite.Assert().Equal(step.StartedAt, time)
	suite.Assert().Equal(step.CompletedAt, time)
	suite.Assert().Equal(step.Status, checks.CheckStatus_STATUS_COMPLETED)
	suite.Assert().Equal(step.Conclusion, checks.CheckConclusion_CONCLUSION_SUCCESS)
	suite.Assert().Nil(step.CompletedLogUrl)
	suite.Assert().Nil(step.CompletedLogLines)
}

func (suite *resultsStatusServiceSuite) Test_getEnvironmentResults_ValidEnvironment_ReturnsResultsEnvironment() {
	testEnvironment := &Environment{
		Name: "testEnvironmentName",
		Url:  "testEnvironmentURL",
	}

	environment := getEnvironmentResults(testEnvironment)

	suite.Assert().Equal(environment.Name, "testEnvironmentName")
	suite.Assert().Equal(environment.Url, "testEnvironmentURL")
}

func (suite *resultsStatusServiceSuite) Test_getEnvironmentResults_NilEnvironment_ReturnsNilResultsEnvironment() {
	var testEnvironment *Environment

	environment := getEnvironmentResults(testEnvironment)

	suite.Assert().Nil(environment)
}
func (s *resultsStatusServiceSuite) getTimings() (*time.Time, *timestamp.Timestamp, *time.Time, *timestamp.Timestamp) {
	startedAt := time.Date(2000, 1, 1, 10, 0, 0, 1, time.UTC)
	startedAtProto := timestamppb.New(startedAt)

	completedAt := startedAt.Add(time.Second * 10)
	completedAtProto := timestamppb.New(completedAt)

	return &startedAt, startedAtProto, &completedAt, completedAtProto
}
