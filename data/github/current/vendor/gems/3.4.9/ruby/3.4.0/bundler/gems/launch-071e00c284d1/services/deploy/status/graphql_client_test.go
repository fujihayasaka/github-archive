package status

import (
	"context"
	http "net/http"
	"testing"
	"time"

	"github.com/golang/protobuf/ptypes/timestamp"
	errs "github.com/pkg/errors"
	mock "github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/suite"
	"google.golang.org/protobuf/types/known/timestamppb"

	"github.com/github/launch/clients/ghtwirp"
	"github.com/github/launch/clients/github"
	"github.com/github/launch/clients/github/tokens"
	"github.com/github/launch/clients/hydro/metadata"
	"github.com/github/launch/db/stores/deployer"
	"github.com/github/launch/observability/logger"
	"github.com/github/launch/observability/statter"
	"github.com/github/launch/types"
	"github.com/github/launch/types/errors"
)

var (
	testRepoGlobalID = types.GlobalID("R_kgAD=")
	testOrgGlobalID  = types.GlobalID("O_kgDNJr8")
)

func TestGraphQLStatusClient(t *testing.T) {
	suite.Run(t, new(gqlStatusServiceSuite))
}

type gqlStatusServiceSuite struct {
	suite.Suite

	client *graphQLStatusClient

	ghClient        *github.MockClient
	ghClientFactory *github.MockFactory
	wfbRepo         *deployer.MockWorkflowBuildsRepository
	ghTwirpClient   *ghtwirp.MockClient
}

// helper function to return some ts
func (gqls *gqlStatusServiceSuite) getTimings() (*time.Time, *timestamp.Timestamp, *time.Time, *timestamp.Timestamp) {
	startedAt := time.Date(2000, 1, 1, 10, 0, 0, 1, time.UTC)
	startedAtProto := timestamppb.New(startedAt)

	completedAt := startedAt.Add(time.Second * 10)
	completedAtProto := timestamppb.New(completedAt)

	return &startedAt, startedAtProto, &completedAt, completedAtProto
}

func (gqls *gqlStatusServiceSuite) SetupTest() {
	gqls.wfbRepo = &deployer.MockWorkflowBuildsRepository{}
	gqls.ghClientFactory = &github.MockFactory{}
	gqls.ghClient = &github.MockClient{}
	gqls.ghTwirpClient = &ghtwirp.MockClient{}

	gqls.wfbRepo.On(
		"GetDataForTokenRequest",
		mock.Anything,
		testWorkflowID,
	).Return(&deployer.DataForTokenRequest{
		TokenPermissions: &tokens.PermissionSettings{
			InstallationPermissions: *tokens.NewInstallationPermissions(tokens.WritePermissions),
			DefaultPermissions:      tokens.WritePermissions,
		},
		RepositoryID:     testRepoGlobalID,
		WorkflowMetadata: &metadata.WorkflowMetadata{},
	}, true, nil)

	client := newGraphQLStatusClient(
		logger.TestLogger(),
		logger.TestLogger(),
		clientConfig{
			repoConfig: &repoConfig{
				workflowID: testWorkflowID,
				buildRepo:  gqls.wfbRepo,
			},
			ghFactory:     gqls.ghClientFactory,
			ghTwirpClient: gqls.ghTwirpClient,
		},
		statter.NullStatter(),
		false,
	)

	gqls.NotNil(client, "GraphQLStatusClient is nil")

	gqls.ghClientFactory.On("NewClientForRepositoryOwner",
		mock.Anything,
		testRepoGlobalID,
		testOrgGlobalID,
	).Return(gqls.ghClient, nil)
	gqls.ghClientFactory.On("NewClientForRepository", mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(gqls.ghClient, nil)

	gqls.client = client
}

func (gqls *gqlStatusServiceSuite) Test_ClientNotFound() {
	ghClientFactory := &github.MockFactory{}

	ghClientFactory.On("NewClientForRepository", mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(
		nil,
		errors.NewHTTPError(&http.Response{StatusCode: 404}),
	).Once()

	jsr := JobStatusRequest{
		WorkflowId:  testWorkflowID,
		JobId:       testJobIDA,
		ExternalId:  testExternalID,
		DisplayName: testJobNameA,
		Number:      1,
		Progress: &JobStatusRequest_InProgress{
			InProgress: &JobInProgress{
				Status: Status_STATUS_PENDING,
			},
		},
		Steps:           []*JobStep{},
		Labels:          []string{"foo", "bar"},
		RunnerId:        testRunnerID,
		RunnerName:      testRunnerName,
		RunnerGroupId:   testRunnerGroupID,
		RunnerGroupName: testRunnerGroupName,
	}
	waitingOn := WaitingOn{}
	gqlClient := newGraphQLStatusClient(logger.TestLogger(), logger.TestLogger(), clientConfig{repoConfig: &repoConfig{workflowID: testWorkflowID, buildRepo: gqls.wfbRepo}, ghFactory: ghClientFactory, ghTwirpClient: gqls.ghTwirpClient}, statter.NullStatter(), false)
	err := gqlClient.UpdateCheckRun(context.Background(), &jsr, UpdateCheckRunParams{CheckSuiteState: &testCheckSuiteState, WaitingOn: &waitingOn, CheckRunID: testCheckRunID})
	gqls.Error(err)

	ghClientFactory.AssertExpectations(gqls.T())
}

func (gqls *gqlStatusServiceSuite) Test_InProgressJob_CreatesExpectedCheckRun() {
	startedAt, startedAtProto, _, _ := gqls.getTimings()
	waitingOn := WaitingOn{}

	gqls.ghClient.On(
		"CreateCheckRun",
		mock.Anything,
		github.CreateCheckRunRequest{
			RepositoryID: testRepositoryID,
			CheckSuiteID: testCheckSuiteID,
			ExternalID:   testExternalID,
			HeadSHA:      testCommitSHA,
			Name:         testJobIDA,
			DisplayName:  testJobNameA,
			Number:       1,
			Status:       "IN_PROGRESS",
			StartedAt:    startedAt,
			Steps: []github.CheckStepData{
				{
					ExternalID:   "some-step-external-id",
					Name:         "some-step-name",
					Number:       456,
					StartedAt:    startedAt,
					Status:       "IN_PROGRESS",
					CompletedLog: nil,
					CompletedAt:  nil,
					Conclusion:   "",
				},
			},
		},
	).Return(testCheckRunResponse, nil).Once()

	gqls.ghClientFactory.ExpectedCalls = []*mock.Call{} // reset mocks
	gqls.ghClientFactory.
		On("NewClientForRepository",
			mock.Anything,
			testRepoGlobalID,
			types.NilGlobalID,
			mock.MatchedBy(func(opts *github.ClientTokenOptions) bool {
				isCorrectPermissions := opts.TokenPermissions.Checks == tokens.WriteAccess &&
					opts.TokenPermissions.Deployments == tokens.WriteAccess
				return opts.UseTokenCache && isCorrectPermissions
			}),
		).Return(gqls.ghClient, nil)

	jsr := JobStatusRequest{
		WorkflowId:  testWorkflowID,
		JobId:       testJobIDA,
		ExternalId:  testExternalID,
		DisplayName: testJobNameA,
		Number:      1,
		Progress: &JobStatusRequest_InProgress{
			InProgress: &JobInProgress{
				Status:    Status_STATUS_IN_PROGRESS,
				StartedAt: startedAtProto,
			},
		},
		Steps: []*JobStep{
			{
				ExternalId: "some-step-external-id",
				Name:       "some-step-name",
				Number:     456,
				Progress: &JobStep_InProgress{
					InProgress: &StepInProgress{
						Status:    Status_STATUS_IN_PROGRESS,
						StartedAt: startedAtProto,
					},
				},
			},
		},
	}

	idPair, err := gqls.client.CreateCheckRun(context.Background(), &jsr, CreateCheckRunParams{CheckSuiteState: &testCheckSuiteState, WaitingOn: &waitingOn})
	gqls.NoError(err)
	gqls.Equal(testCheckRunID, idPair.GlobalID)
	gqls.ghClient.AssertExpectations(gqls.T())
	gqls.ghClientFactory.AssertExpectations(gqls.T())
}

func (gqls *gqlStatusServiceSuite) Test_InProgressJobWithLog_CreatesExpectedCheckRun() {
	startedAt, startedAtProto, _, _ := gqls.getTimings()
	waitingOn := WaitingOn{}

	gqls.ghClient.On(
		"CreateCheckRun",
		mock.Anything,
		github.CreateCheckRunRequest{
			RepositoryID: testRepositoryID,
			CheckSuiteID: testCheckSuiteID,
			ExternalID:   testExternalID,
			HeadSHA:      testCommitSHA,
			Name:         testJobIDA,
			DisplayName:  testJobNameA,
			Number:       1,
			Status:       "IN_PROGRESS",
			StartedAt:    startedAt,
			CompletedLog: &github.CompletedLog{
				URL:   testJobLogsURL,
				Lines: 1,
			},
			Steps: []github.CheckStepData{
				{
					ExternalID:   "some-step-external-id",
					Name:         "some-step-name",
					Number:       456,
					StartedAt:    startedAt,
					Status:       "IN_PROGRESS",
					CompletedLog: nil,
					CompletedAt:  nil,
					Conclusion:   "",
				},
			},
		},
	).Return(testCheckRunResponse, nil).Once()

	jsr := JobStatusRequest{
		WorkflowId:  testWorkflowID,
		JobId:       testJobIDA,
		ExternalId:  testExternalID,
		DisplayName: testJobNameA,
		Number:      1,
		Progress: &JobStatusRequest_InProgress{
			InProgress: &JobInProgress{
				Status:    Status_STATUS_IN_PROGRESS,
				StartedAt: startedAtProto,
				Log: &Log{
					Url:       testJobLogsURL,
					Lines:     1,
					CreatedAt: startedAtProto,
				},
			},
		},
		Steps: []*JobStep{
			{
				ExternalId: "some-step-external-id",
				Name:       "some-step-name",
				Number:     456,
				Progress: &JobStep_InProgress{
					InProgress: &StepInProgress{
						Status:    Status_STATUS_IN_PROGRESS,
						StartedAt: startedAtProto,
					},
				},
			},
		},
	}

	idPair, err := gqls.client.CreateCheckRun(context.Background(), &jsr, CreateCheckRunParams{CheckSuiteState: &testCheckSuiteState, WaitingOn: &waitingOn})
	gqls.NoError(err)
	gqls.Equal(testCheckRunID, idPair.GlobalID)
	_ = gqls.ghClient.AssertExpectations(gqls.T())
}

func (gqls *gqlStatusServiceSuite) Test_EnvironmentWithName_CreatesExpectedCheckRun() {
	startedAt, startedAtProto, _, _ := gqls.getTimings()
	waitingOn := WaitingOn{}

	gqls.ghClient.On(
		"CreateCheckRun",
		mock.Anything,
		github.CreateCheckRunRequest{
			RepositoryID: testRepositoryID,
			CheckSuiteID: testCheckSuiteID,
			ExternalID:   testExternalID,
			HeadSHA:      testCommitSHA,
			Name:         testJobIDA,
			DisplayName:  testJobNameA,
			Number:       1,
			Status:       "IN_PROGRESS",
			StartedAt:    startedAt,
			Steps: []github.CheckStepData{
				{
					ExternalID:   "some-step-external-id",
					Name:         "some-step-name",
					Number:       456,
					StartedAt:    startedAt,
					Status:       "IN_PROGRESS",
					CompletedLog: nil,
					CompletedAt:  nil,
					Conclusion:   "",
				},
			},
			EnvironmentName: "staging",
		},
	).Return(testCheckRunResponse, nil).Once()

	jsr := JobStatusRequest{
		WorkflowId:  testWorkflowID,
		JobId:       testJobIDA,
		ExternalId:  testExternalID,
		DisplayName: testJobNameA,
		Number:      1,
		Progress: &JobStatusRequest_InProgress{
			InProgress: &JobInProgress{
				Status:    Status_STATUS_IN_PROGRESS,
				StartedAt: startedAtProto,
			},
		},
		Steps: []*JobStep{
			{
				ExternalId: "some-step-external-id",
				Name:       "some-step-name",
				Number:     456,
				Progress: &JobStep_InProgress{
					InProgress: &StepInProgress{
						Status:    Status_STATUS_IN_PROGRESS,
						StartedAt: startedAtProto,
					},
				},
			},
		},
		Environment: &Environment{
			Name: "staging",
		},
	}

	idPair, err := gqls.client.CreateCheckRun(context.Background(), &jsr, CreateCheckRunParams{CheckSuiteState: &testCheckSuiteState, WaitingOn: &waitingOn})
	gqls.NoError(err)
	gqls.Equal(testCheckRunID, idPair.GlobalID)
	_ = gqls.ghClient.AssertExpectations(gqls.T())
}

func (gqls *gqlStatusServiceSuite) Test_Concurrency_CreatesExpectedCheckRun() {
	waitingOn := WaitingOn{
		CheckRunID: testWaitingOnCheckRunID,
	}

	gqls.ghClient.On(
		"CreateCheckRun",
		mock.Anything,
		github.CreateCheckRunRequest{
			RepositoryID: testRepositoryID,
			CheckSuiteID: testCheckSuiteID,
			ExternalID:   testExternalID,
			HeadSHA:      testCommitSHA,
			Name:         testJobIDA,
			DisplayName:  testJobNameA,
			Number:       1,
			Status:       "PENDING",
			Steps: []github.CheckStepData{
				{
					ExternalID:   "some-step-external-id",
					Name:         "some-step-name",
					Number:       456,
					Status:       "QUEUED",
					CompletedLog: nil,
					CompletedAt:  nil,
					Conclusion:   "",
				},
			},
			Concurrency: &github.Concurrency{
				Group: "testGroup",
				WaitingOnResource: &github.WaitingOnResource{
					CheckSuiteID: "",
					CheckRunID:   testWaitingOnCheckRunID,
				},
			},
		},
	).Return(testCheckRunResponse, nil).Once()

	jsr := JobStatusRequest{
		WorkflowId:  testWorkflowID,
		JobId:       testJobIDA,
		ExternalId:  testExternalID,
		DisplayName: testJobNameA,
		Number:      1,
		Progress: &JobStatusRequest_InProgress{
			InProgress: &JobInProgress{
				Status: Status_STATUS_PENDING,
			},
		},
		Steps: []*JobStep{
			{
				ExternalId: "some-step-external-id",
				Name:       "some-step-name",
				Number:     456,
				Progress: &JobStep_Queued{
					Queued: &StepQueued{},
				},
			},
		},
		Concurrency: &Concurrency{
			Group: "testGroup",
			WaitingOnResource: &WaitingOnResource{
				RunExternalId: "",
				JobExternalId: "7932bae7-53d0-4c3a-a367-6796ce577dba,3032fcfd-deae-56f7-b0ea-1caf60f8b58a",
			},
		},
	}

	idPair, err := gqls.client.CreateCheckRun(context.Background(), &jsr, CreateCheckRunParams{CheckSuiteState: &testCheckSuiteState, WaitingOn: &waitingOn})
	gqls.NoError(err)
	gqls.Equal(testCheckRunID, idPair.GlobalID)
	_ = gqls.ghClient.AssertExpectations(gqls.T())
}

func (gqls *gqlStatusServiceSuite) Test_JobStatus_Concurrency_WaitingOnCalledJob() {
	waitingOn := WaitingOn{
		CheckSuiteID: testWaitingOnCheckSuiteID,
	}

	gqls.ghClient.On(
		"CreateCheckRun",
		mock.Anything,
		github.CreateCheckRunRequest{
			RepositoryID: testRepositoryID,
			CheckSuiteID: testCheckSuiteID,
			ExternalID:   testExternalID,
			HeadSHA:      testCommitSHA,
			Name:         testJobIDA,
			DisplayName:  testJobNameA,
			Number:       1,
			Status:       "PENDING",
			Steps: []github.CheckStepData{
				{
					ExternalID:   "some-step-external-id",
					Name:         "some-step-name",
					Number:       456,
					Status:       "QUEUED",
					CompletedLog: nil,
					CompletedAt:  nil,
					Conclusion:   "",
				},
			},
			Concurrency: &github.Concurrency{
				Group: "testGroup",
				WaitingOnResource: &github.WaitingOnResource{
					CheckSuiteID: testWaitingOnCheckSuiteID,
					CheckRunID:   "",
					Identifier:   "test",
				},
			},
		},
	).Return(testCheckRunResponse, nil).Once()

	jsr := JobStatusRequest{
		WorkflowId:  testWorkflowID,
		JobId:       testJobIDA,
		ExternalId:  testExternalID,
		DisplayName: testJobNameA,
		Number:      1,
		Progress: &JobStatusRequest_InProgress{
			InProgress: &JobInProgress{
				Status: Status_STATUS_PENDING,
			},
		},
		Steps: []*JobStep{
			{
				ExternalId: "some-step-external-id",
				Name:       "some-step-name",
				Number:     456,
				Progress: &JobStep_Queued{
					Queued: &StepQueued{},
				},
			},
		},
		Concurrency: &Concurrency{
			Group: "testGroup",
			WaitingOnResource: &WaitingOnResource{
				RunExternalId: "7932bae7-53d0-4c3a-a367-6796ce577dba",
				JobExternalId: "7932bae7-53d0-4c3a-a367-6796ce577dba,3032fcfd-deae-56f7-b0ea-1caf60f8b58a",
				Identifier:    "test",
			},
		},
	}

	idPair, err := gqls.client.CreateCheckRun(context.Background(), &jsr, CreateCheckRunParams{CheckSuiteState: &testCheckSuiteState, WaitingOn: &waitingOn})
	gqls.NoError(err)
	gqls.Equal(testCheckRunID, idPair.GlobalID)
	_ = gqls.ghClient.AssertExpectations(gqls.T())
}

func (gqls *gqlStatusServiceSuite) Test_CreatesCheckRunWithLabels() {
	waitingOn := WaitingOn{}

	gqls.ghClient.On(
		"CreateCheckRun",
		mock.Anything,
		github.CreateCheckRunRequest{
			RepositoryID: testRepositoryID,
			CheckSuiteID: testCheckSuiteID,
			ExternalID:   testExternalID,
			HeadSHA:      testCommitSHA,
			Name:         testJobIDA,
			DisplayName:  testJobNameA,
			Number:       1,
			Status:       "PENDING",
			Labels:       []string{"foo", "bar"},
			RunnerID:     testRunnerID,
			RunnerName:   testRunnerName,
		},
	).Return(testCheckRunResponse, nil).Once()

	jsr := JobStatusRequest{
		WorkflowId:  testWorkflowID,
		JobId:       testJobIDA,
		ExternalId:  testExternalID,
		DisplayName: testJobNameA,
		Number:      1,
		Progress: &JobStatusRequest_InProgress{
			InProgress: &JobInProgress{
				Status: Status_STATUS_PENDING,
			},
		},
		Steps:      []*JobStep{},
		Labels:     []string{"foo", "bar"},
		RunnerId:   testRunnerID,
		RunnerName: testRunnerName,
	}

	idPair, err := gqls.client.CreateCheckRun(context.Background(), &jsr, CreateCheckRunParams{CheckSuiteState: &testCheckSuiteState, WaitingOn: &waitingOn})
	gqls.NoError(err)
	gqls.Equal(testCheckRunID, idPair.GlobalID)
	_ = gqls.ghClient.AssertExpectations(gqls.T())
}

func (gqls *gqlStatusServiceSuite) Test_UpdatesCheckRunWithLabels() {
	waitingOn := WaitingOn{}

	gqls.ghClient.On(
		"UpdateCheckRun",
		mock.Anything,
		github.UpdateCheckRunRequest{
			RepositoryID:    testRepositoryID,
			CheckRunID:      testCheckRunID,
			ExternalID:      testExternalID,
			Name:            testJobIDA,
			DisplayName:     testJobNameA,
			Number:          1,
			Status:          "PENDING",
			Labels:          []string{"foo", "bar"},
			RunnerID:        testRunnerID,
			RunnerName:      testRunnerName,
			RunnerGroupID:   testRunnerGroupID,
			RunnerGroupName: testRunnerGroupName,
		},
	).Return(testCheckRunResponse, nil).Once()

	jsr := JobStatusRequest{
		WorkflowId:  testWorkflowID,
		JobId:       testJobIDA,
		ExternalId:  testExternalID,
		DisplayName: testJobNameA,
		Number:      1,
		Progress: &JobStatusRequest_InProgress{
			InProgress: &JobInProgress{
				Status: Status_STATUS_PENDING,
			},
		},
		Steps:           []*JobStep{},
		Labels:          []string{"foo", "bar"},
		RunnerId:        testRunnerID,
		RunnerName:      testRunnerName,
		RunnerGroupId:   testRunnerGroupID,
		RunnerGroupName: testRunnerGroupName,
	}

	err := gqls.client.UpdateCheckRun(context.Background(), &jsr, UpdateCheckRunParams{CheckSuiteState: &testCheckSuiteState, WaitingOn: &waitingOn, CheckRunID: testCheckRunID})
	gqls.NoError(err)
	_ = gqls.ghClient.AssertExpectations(gqls.T())
}

func (gqls *gqlStatusServiceSuite) Test_NotStartedJob_CreatesExpectedCheckRun() {
	waitingOn := WaitingOn{}

	gqls.ghClient.On(
		"CreateCheckRun",
		mock.Anything,
		github.CreateCheckRunRequest{
			RepositoryID: testRepositoryID,
			CheckSuiteID: testCheckSuiteID,
			ExternalID:   testExternalID,
			HeadSHA:      testCommitSHA,
			Name:         testJobIDA,
			DisplayName:  testJobNameA,
			Number:       1,
			Status:       "QUEUED",
		},
	).Return(testCheckRunResponse, nil).Once()

	jsr := JobStatusRequest{
		WorkflowId:  testWorkflowID,
		JobId:       testJobIDA,
		ExternalId:  testExternalID,
		DisplayName: testJobNameA,
		Number:      1,
		Progress: &JobStatusRequest_InProgress{
			InProgress: &JobInProgress{
				Status:    Status_STATUS_NOT_STARTED,
				StartedAt: nil,
			},
		},
	}

	idPair, err := gqls.client.CreateCheckRun(context.Background(), &jsr, CreateCheckRunParams{CheckSuiteState: &testCheckSuiteState, WaitingOn: &waitingOn})
	gqls.NoError(err)
	gqls.Equal(testCheckRunID, idPair.GlobalID)
	_ = gqls.ghClient.AssertExpectations(gqls.T())
}

func (gqls *gqlStatusServiceSuite) Test_InProgressJob_CreatesExpectedCheckRunWithStartedAt() {
	startedAt, startedAtProto, _, _ := gqls.getTimings()
	waitingOn := WaitingOn{}

	gqls.ghClient.On(
		"CreateCheckRun",
		mock.Anything,
		github.CreateCheckRunRequest{
			RepositoryID: testRepositoryID,
			CheckSuiteID: testCheckSuiteID,
			ExternalID:   testExternalID,
			HeadSHA:      testCommitSHA,
			Name:         testJobIDA,
			DisplayName:  testJobNameA,
			Number:       1,
			Status:       "IN_PROGRESS",
			StartedAt:    startedAt,
			Steps: []github.CheckStepData{
				{
					ExternalID:   "some-step-external-id",
					Name:         "some-step-name",
					Number:       456,
					StartedAt:    startedAt,
					Status:       "IN_PROGRESS",
					CompletedLog: nil,
					CompletedAt:  nil,
					Conclusion:   "",
				},
			},
		},
	).Return(testCheckRunResponse, nil).Once()

	jsr := JobStatusRequest{
		WorkflowId:  testWorkflowID,
		JobId:       testJobIDA,
		ExternalId:  testExternalID,
		DisplayName: testJobNameA,
		Number:      1,
		Progress: &JobStatusRequest_InProgress{
			InProgress: &JobInProgress{
				Status:    Status_STATUS_IN_PROGRESS,
				StartedAt: startedAtProto,
			},
		},
		Steps: []*JobStep{
			{
				ExternalId: "some-step-external-id",
				Name:       "some-step-name",
				Number:     456,
				Progress: &JobStep_InProgress{
					InProgress: &StepInProgress{
						Status:    Status_STATUS_IN_PROGRESS,
						StartedAt: startedAtProto,
					},
				},
			},
		},
	}

	idPair, err := gqls.client.CreateCheckRun(context.Background(), &jsr, CreateCheckRunParams{CheckSuiteState: &testCheckSuiteState, WaitingOn: &waitingOn})
	gqls.NoError(err)
	gqls.Equal(testCheckRunID, idPair.GlobalID)
	_ = gqls.ghClient.AssertExpectations(gqls.T())
}

func (gqls *gqlStatusServiceSuite) Test_SkippedJob_CreatesSkippedCheckRun() {
	startedAt, startedAtProto, completedAt, completedAtProto := gqls.getTimings()
	waitingOn := WaitingOn{}

	gqls.ghClient.On(
		"CreateCheckRun",
		mock.Anything,
		github.CreateCheckRunRequest{
			RepositoryID: testRepositoryID,
			CheckSuiteID: testCheckSuiteID,
			ExternalID:   testExternalID,
			HeadSHA:      testCommitSHA,
			Name:         testJobIDA,
			DisplayName:  testJobNameA,
			Number:       1,
			Status:       "COMPLETED",
			Conclusion:   "SKIPPED",
			StartedAt:    startedAt,
			CompletedAt:  completedAt,
		},
	).Return(testCheckRunResponse, nil).Once()

	jsr := JobStatusRequest{
		WorkflowId:  testWorkflowID,
		JobId:       testJobIDA,
		ExternalId:  testExternalID,
		DisplayName: testJobNameA,
		Number:      1,
		Progress: &JobStatusRequest_Complete{
			Complete: &JobComplete{
				Result:      Result_RESULT_SKIPPED,
				StartedAt:   startedAtProto,
				CompletedAt: completedAtProto,
			},
		},
	}

	idPair, err := gqls.client.CreateCheckRun(context.Background(), &jsr, CreateCheckRunParams{CheckSuiteState: &testCheckSuiteState, WaitingOn: &waitingOn})
	gqls.NoError(err)
	gqls.Equal(testCheckRunID, idPair.GlobalID)
	_ = gqls.ghClient.AssertExpectations(gqls.T())
}

func (gqls *gqlStatusServiceSuite) Test_SuccessfulJobWithAnnotations_UpdatesExpectedCheckRun() {
	_, startedAtProto, _, completedAtProto := gqls.getTimings()
	waitingOn := WaitingOn{}

	gqls.ghClient.On(
		"UpdateCheckRun",
		mock.Anything,
		mock.MatchedBy(func(req github.UpdateCheckRunRequest) bool {
			if len(req.Output.Annotations) != 1 {
				return false
			}
			a := req.Output.Annotations[0]
			return a.AnnotationLevel == AnnotationNotice &&
				a.Message == "message" &&
				a.RawDetails == "raw details" &&
				a.Path == "path" &&
				a.Title == "title" &&
				a.Location.StartLine == 2 &&
				a.Location.EndLine == 2 &&
				a.Location.StartColumn == 1 &&
				a.Location.EndColumn == 5 &&
				a.Location.StepNumber == 3
		}),
	).Return(testCheckRunResponse, nil).Once()

	jsr := JobStatusRequest{
		WorkflowId:  testWorkflowID,
		JobId:       testJobIDA,
		ExternalId:  testExternalID,
		DisplayName: testJobNameA,
		Number:      1,
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
		Annotations: []*Annotation{
			{
				AnnotationLevel: AnnotationLevel_LEVEL_NOTICE,
				Message:         "message",
				RawDetails:      "raw details",
				Path:            "path",
				StartLine:       2,
				EndLine:         2,
				StartColumn:     1,
				EndColumn:       5,
				StepNumber:      3,
				Title:           "title",
			},
		},
	}

	err := gqls.client.UpdateCheckRun(context.Background(), &jsr, UpdateCheckRunParams{CheckSuiteState: &testCheckSuiteState, WaitingOn: &waitingOn, CheckRunID: testCheckRunID})
	gqls.NoError(err)
	_ = gqls.ghClient.AssertExpectations(gqls.T())
}

func (gqls *gqlStatusServiceSuite) Test_JobWithNilEnvironment_CreatesExpectedCheckRun() {
	_, startedAtProto, _, _ := gqls.getTimings()
	waitingOn := WaitingOn{}

	gqls.ghClient.On(
		"UpdateCheckRun",
		mock.Anything,
		mock.MatchedBy(func(req github.UpdateCheckRunRequest) bool {
			return req.EnvironmentURL == "" && req.EnvironmentName == ""
		}),
	).Return(testCheckRunResponse, nil).Once()

	jsr := JobStatusRequest{
		WorkflowId:  testWorkflowID,
		JobId:       testJobIDA,
		ExternalId:  testExternalID,
		DisplayName: testJobNameA,
		Number:      1,
		Progress: &JobStatusRequest_InProgress{
			InProgress: &JobInProgress{
				Status:    Status_STATUS_IN_PROGRESS,
				StartedAt: startedAtProto,
			},
		},
		Environment: nil,
	}

	err := gqls.client.UpdateCheckRun(context.Background(), &jsr, UpdateCheckRunParams{CheckSuiteState: &testCheckSuiteState, WaitingOn: &waitingOn, CheckRunID: testCheckRunID})
	gqls.NoError(err)
	_ = gqls.ghClient.AssertExpectations(gqls.T())
}

func (gqls *gqlStatusServiceSuite) Test_JobWithEnvironmentName_CreatesExpectedCheckRun() {
	_, startedAtProto, _, _ := gqls.getTimings()
	waitingOn := WaitingOn{}

	gqls.ghClient.On(
		"UpdateCheckRun",
		mock.Anything,
		mock.MatchedBy(func(req github.UpdateCheckRunRequest) bool {
			return req.EnvironmentURL == "" && req.EnvironmentName == "staging"
		}),
	).Return(testCheckRunResponse, nil).Once()

	jsr := JobStatusRequest{
		WorkflowId:  testWorkflowID,
		JobId:       testJobIDA,
		ExternalId:  testExternalID,
		DisplayName: testJobNameA,
		Number:      1,
		Progress: &JobStatusRequest_InProgress{
			InProgress: &JobInProgress{
				Status:    Status_STATUS_IN_PROGRESS,
				StartedAt: startedAtProto,
			},
		},
		Environment: &Environment{
			Name: "staging",
		},
	}

	err := gqls.client.UpdateCheckRun(context.Background(), &jsr, UpdateCheckRunParams{CheckSuiteState: &testCheckSuiteState, WaitingOn: &waitingOn, CheckRunID: testCheckRunID})
	gqls.NoError(err)
	_ = gqls.ghClient.AssertExpectations(gqls.T())
}

func (gqls *gqlStatusServiceSuite) Test_JobWithEnvironmentNameAndUrl_CreatesExpectedCheckRun() {
	_, startedAtProto, _, _ := gqls.getTimings()
	waitingOn := WaitingOn{}

	gqls.ghClient.On(
		"UpdateCheckRun",
		mock.Anything,
		mock.MatchedBy(func(req github.UpdateCheckRunRequest) bool {
			return req.EnvironmentURL == "http://github.com" && req.EnvironmentName == "staging"
		}),
	).Return(testCheckRunResponse, nil).Once()

	jsr := JobStatusRequest{
		WorkflowId:  testWorkflowID,
		JobId:       testJobIDA,
		ExternalId:  testExternalID,
		DisplayName: testJobNameA,
		Number:      1,
		Progress: &JobStatusRequest_InProgress{
			InProgress: &JobInProgress{
				Status:    Status_STATUS_IN_PROGRESS,
				StartedAt: startedAtProto,
			},
		},
		Environment: &Environment{
			Name: "staging",
			Url:  "http://github.com",
		},
	}

	err := gqls.client.UpdateCheckRun(context.Background(), &jsr, UpdateCheckRunParams{CheckSuiteState: &testCheckSuiteState, WaitingOn: &waitingOn, CheckRunID: testCheckRunID})
	gqls.NoError(err)
	_ = gqls.ghClient.AssertExpectations(gqls.T())
}

func (gqls *gqlStatusServiceSuite) Test_SuccessfulJobWithoutLogs_CreatesExpectedCheckRun() {
	startedAt, startedAtProto, completedAt, completedAtProto := gqls.getTimings()
	waitingOn := WaitingOn{}

	gqls.ghClient.On(
		"CreateCheckRun",
		mock.Anything,
		github.CreateCheckRunRequest{
			RepositoryID: testRepositoryID,
			CheckSuiteID: testCheckSuiteID,
			ExternalID:   testExternalID,
			HeadSHA:      testCommitSHA,
			DisplayName:  testJobNameA,
			Name:         testJobIDA,
			Number:       1,
			Status:       "COMPLETED",
			Conclusion:   "SUCCESS",
			StartedAt:    startedAt,
			CompletedAt:  completedAt,
			Steps: []github.CheckStepData{
				{
					ExternalID:  "some-step-external-id",
					Name:        "some-step-name",
					Number:      456,
					StartedAt:   startedAt,
					Status:      "COMPLETED",
					Conclusion:  "SUCCESS",
					CompletedAt: completedAt,
					CompletedLog: &github.CompletedLog{
						URL:   "http://some-step-log.log",
						Lines: 2,
					},
				},
			},
		},
	).Return(testCheckRunResponse, nil).Once()

	jsr := JobStatusRequest{
		WorkflowId:  testWorkflowID,
		JobId:       testJobIDA,
		ExternalId:  testExternalID,
		DisplayName: testJobNameA,
		Number:      1,
		Progress: &JobStatusRequest_Complete{
			Complete: &JobComplete{
				Result:      Result_RESULT_SUCCEEDED,
				StartedAt:   startedAtProto,
				CompletedAt: completedAtProto,
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

	idPair, err := gqls.client.CreateCheckRun(context.Background(), &jsr, CreateCheckRunParams{CheckSuiteState: &testCheckSuiteState, WaitingOn: &waitingOn})
	gqls.NoError(err)
	gqls.Equal(testCheckRunID, idPair.GlobalID)
	_ = gqls.ghClient.AssertExpectations(gqls.T())
}

func (gqls *gqlStatusServiceSuite) Test_SuccessfulJob_CorrectlyUpdatesCheckRunWithoutLogs_IfCheckRunExists() {
	startedAt, startedAtProto, completedAt, completedAtProto := gqls.getTimings()
	waitingOn := WaitingOn{}

	gqls.ghClient.On(
		"UpdateCheckRun",
		mock.Anything,
		github.UpdateCheckRunRequest{
			RepositoryID: testRepositoryID,
			CheckRunID:   testCheckRunID,
			Name:         testJobIDA,
			DisplayName:  testJobNameB,
			Number:       1,
			Status:       "COMPLETED",
			Conclusion:   "SUCCESS",
			StartedAt:    startedAt,
			CompletedAt:  completedAt,
			ExternalID:   testExternalID,
			Steps: []github.CheckStepData{
				{
					ExternalID:  "some-step-external-id",
					Name:        "some-step-name",
					Number:      456,
					StartedAt:   startedAt,
					Status:      "COMPLETED",
					Conclusion:  "SUCCESS",
					CompletedAt: completedAt,
					CompletedLog: &github.CompletedLog{
						URL:   "http://some-step-log.log",
						Lines: 2,
					},
				},
			},
		},
	).Return(testCheckRunResponse, nil).Once()

	jsr := JobStatusRequest{
		WorkflowId:  testWorkflowID,
		DisplayName: testJobNameB,
		Number:      1,
		JobId:       testJobIDA,
		ExternalId:  testExternalID,
		Progress: &JobStatusRequest_Complete{
			Complete: &JobComplete{
				Result:      Result_RESULT_SUCCEEDED,
				StartedAt:   startedAtProto,
				CompletedAt: completedAtProto,
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

	err := gqls.client.UpdateCheckRun(context.Background(), &jsr, UpdateCheckRunParams{CheckSuiteState: &testCheckSuiteState, WaitingOn: &waitingOn, CheckRunID: testCheckRunID})
	gqls.NoError(err)
	_ = gqls.ghClient.AssertExpectations(gqls.T())
}

func (gqls *gqlStatusServiceSuite) Test_CreateCheckRun_AddsSummaryURLOnComplete_IfExists() {
	startedAt, startedAtProto, completedAt, completedAtProto := gqls.getTimings()
	waitingOn := WaitingOn{}

	gqls.ghClient.On(
		"CreateCheckRun",
		mock.Anything,
		github.CreateCheckRunRequest{
			RepositoryID: testRepositoryID,
			CheckSuiteID: testCheckSuiteID,
			ExternalID:   testExternalID,
			HeadSHA:      testCommitSHA,
			DisplayName:  testJobNameA,
			Name:         testJobIDA,
			Number:       1,
			Status:       "COMPLETED",
			Conclusion:   "SUCCESS",
			StartedAt:    startedAt,
			CompletedAt:  completedAt,
			JobSummary: &github.JobSummary{
				URL: "http://some-summary-url.com",
			},
			Steps: []github.CheckStepData{
				{
					ExternalID:  "some-step-external-id",
					Name:        "some-step-name",
					Number:      456,
					StartedAt:   startedAt,
					Status:      "COMPLETED",
					Conclusion:  "SUCCESS",
					CompletedAt: completedAt,
					CompletedLog: &github.CompletedLog{
						URL:   "http://some-step-log.log",
						Lines: 2,
					},
				},
			},
		},
	).Return(testCheckRunResponse, nil).Once()

	jsr := JobStatusRequest{
		WorkflowId:  testWorkflowID,
		JobId:       testJobIDA,
		ExternalId:  testExternalID,
		DisplayName: testJobNameA,
		Number:      1,
		Progress: &JobStatusRequest_Complete{
			Complete: &JobComplete{
				Result:      Result_RESULT_SUCCEEDED,
				StartedAt:   startedAtProto,
				CompletedAt: completedAtProto,
				SummaryUrl:  "http://some-summary-url.com",
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

	idPair, err := gqls.client.CreateCheckRun(context.Background(), &jsr, CreateCheckRunParams{CheckSuiteState: &testCheckSuiteState, WaitingOn: &waitingOn})
	gqls.NoError(err)
	gqls.Equal(testCheckRunID, idPair.GlobalID)
	_ = gqls.ghClient.AssertExpectations(gqls.T())
}

func (gqls *gqlStatusServiceSuite) Test_UpdateCheckRun_AddsSummaryURLOnComplete_IfExists() {
	startedAt, startedAtProto, completedAt, completedAtProto := gqls.getTimings()
	waitingOn := WaitingOn{}

	gqls.ghClient.On(
		"UpdateCheckRun",
		mock.Anything,
		github.UpdateCheckRunRequest{
			RepositoryID: testRepositoryID,
			CheckRunID:   testCheckRunID,
			Name:         testJobIDA,
			DisplayName:  testJobNameB,
			Number:       1,
			Status:       "COMPLETED",
			Conclusion:   "SUCCESS",
			StartedAt:    startedAt,
			CompletedAt:  completedAt,
			ExternalID:   testExternalID,
			JobSummary: &github.JobSummary{
				URL: "http://some-summary-url.com",
			},
			Steps: []github.CheckStepData{
				{
					ExternalID:  "some-step-external-id",
					Name:        "some-step-name",
					Number:      456,
					StartedAt:   startedAt,
					Status:      "COMPLETED",
					Conclusion:  "SUCCESS",
					CompletedAt: completedAt,
					CompletedLog: &github.CompletedLog{
						URL:   "http://some-step-log.log",
						Lines: 2,
					},
				},
			},
		},
	).Return(testCheckRunResponse, nil).Once()

	jsr := JobStatusRequest{
		WorkflowId:  testWorkflowID,
		DisplayName: testJobNameB,
		Number:      1,
		JobId:       testJobIDA,
		ExternalId:  testExternalID,
		Progress: &JobStatusRequest_Complete{
			Complete: &JobComplete{
				Result:      Result_RESULT_SUCCEEDED,
				StartedAt:   startedAtProto,
				CompletedAt: completedAtProto,
				SummaryUrl:  "http://some-summary-url.com",
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

	err := gqls.client.UpdateCheckRun(context.Background(), &jsr, UpdateCheckRunParams{CheckSuiteState: &testCheckSuiteState, WaitingOn: &waitingOn, CheckRunID: testCheckRunID})
	gqls.NoError(err)
	_ = gqls.ghClient.AssertExpectations(gqls.T())
}

func (gqls *gqlStatusServiceSuite) Test_SuccessfulJob_CorrectlyUpdatesCheckRunNoStartedAt_IfCheckRunExists() {
	startedAt, startedAtProto, _, _ := gqls.getTimings()
	waitingOn := WaitingOn{}

	gqls.ghClient.On(
		"UpdateCheckRun",
		mock.Anything,
		github.UpdateCheckRunRequest{
			RepositoryID: testRepositoryID,
			CheckRunID:   testCheckRunID,
			ExternalID:   testExternalID,
			Name:         testJobIDA,
			DisplayName:  testJobNameA,
			Number:       1,
			Status:       "IN_PROGRESS",
			Steps: []github.CheckStepData{
				{
					ExternalID:   "some-step-external-id",
					Name:         "some-step-name",
					Number:       456,
					StartedAt:    startedAt,
					Status:       "IN_PROGRESS",
					CompletedLog: nil,
					CompletedAt:  nil,
					Conclusion:   "",
				},
			},
		},
	).Return(testCheckRunResponse, nil).Once()

	jsr := JobStatusRequest{
		WorkflowId:  testWorkflowID,
		JobId:       testJobIDA,
		ExternalId:  testExternalID,
		DisplayName: testJobNameA,
		Number:      1,
		Progress: &JobStatusRequest_InProgress{
			InProgress: &JobInProgress{
				Status:    Status_STATUS_IN_PROGRESS,
				StartedAt: nil,
			},
		},
		Steps: []*JobStep{
			{
				ExternalId: "some-step-external-id",
				Name:       "some-step-name",
				Number:     456,
				Progress: &JobStep_InProgress{
					InProgress: &StepInProgress{
						Status:    Status_STATUS_IN_PROGRESS,
						StartedAt: startedAtProto,
					},
				},
			},
		},
	}

	err := gqls.client.UpdateCheckRun(context.Background(), &jsr, UpdateCheckRunParams{CheckSuiteState: &testCheckSuiteState, WaitingOn: &waitingOn, CheckRunID: testCheckRunID})
	gqls.NoError(err)
	_ = gqls.ghClient.AssertExpectations(gqls.T())
}

func (gqls *gqlStatusServiceSuite) Test_JobStatus_GraphQLNotFound() {
	waitingOn := WaitingOn{}

	gqlError := errors.NewGraphQLError(errors.NewNotFoundError(errs.New("Not Found")))

	gqls.ghClient.On(
		"UpdateCheckRun",
		mock.Anything,
		mock.Anything,
	).Return(testCheckRunResponse, gqlError).Once()

	jsr := JobStatusRequest{
		WorkflowId:  testWorkflowID,
		JobId:       testJobIDA,
		ExternalId:  testExternalID,
		DisplayName: testJobNameA,
		Number:      1,
		Progress: &JobStatusRequest_InProgress{
			InProgress: &JobInProgress{
				Status:    Status_STATUS_IN_PROGRESS,
				StartedAt: nil,
			},
		},
	}

	err := gqls.client.UpdateCheckRun(context.Background(), &jsr, UpdateCheckRunParams{CheckSuiteState: &testCheckSuiteState, WaitingOn: &waitingOn, CheckRunID: testCheckRunID})
	gqls.ErrorIs(err, gqlError)
}

func (gqls *gqlStatusServiceSuite) Test_RunStatus() {
	artifactsCreatedAt := timestamppb.Now()
	artifactsCreatedAtTime := artifactsCreatedAt.AsTime()

	artifactsExpiresAtTime := artifactsCreatedAtTime.Add(time.Hour * 24)
	artifactsExpiresAtTimeCalculated := getArtifactExpiration(artifactsCreatedAtTime, artifactsExpiresAtTime)
	artifactsExpiresAt := timestamppb.New(artifactsExpiresAtTimeCalculated)

	waitingOn := WaitingOn{}

	gqls.ghClient.On(
		"UpdateCheckSuite",
		mock.Anything,
		github.UpdateCheckSuiteRequest{
			RepositoryID: testRepositoryID,
			CheckSuiteID: testCheckSuiteID,
			Artifacts: []*github.CheckRunArtifact{{
				SourceURL: "",
				Name:      "artifact-a.tar.gz",
				Size:      1024,
				CreatedAt: &artifactsCreatedAtTime,
				ExpiresAt: artifactsExpiresAtTime,
			}, {
				SourceURL: "",
				Name:      "artifact-b.tar.gz",
				Size:      2048,
				CreatedAt: &artifactsCreatedAtTime,
				ExpiresAt: artifactsExpiresAtTime,
			}},
			Conclusion: string(github.CheckSuiteSuccessConclusion),
			Annotations: []github.CheckSuiteAnnotation{
				{
					AnnotationLevel: AnnotationNotice,
					Message:         "message",
					RawDetails:      "raw details",
					Path:            "path",
					Title:           "title",
					Location: github.CheckAnnotationRange{
						StartLine:   2,
						EndLine:     2,
						StartColumn: 1,
						EndColumn:   5,
						StepNumber:  3,
					},
				},
			},
		},
	).Return(&types.IDPair{}, nil).Once()

	rsr := RunStatusRequest{
		WorkflowId: testWorkflowID,
		Artifacts: []*Artifact{{
			Name:      "artifact-a.tar.gz",
			Size:      1024,
			CreatedAt: artifactsCreatedAt,
			ExpiresAt: artifactsExpiresAt,
		}, {
			Name:      "artifact-b.tar.gz",
			Size:      2048,
			CreatedAt: artifactsCreatedAt,
			ExpiresAt: artifactsExpiresAt,
		}},
		Progress: &RunStatusRequest_Complete{
			Complete: &RunComplete{
				StartedAt:   timestamppb.Now(),
				CompletedAt: timestamppb.Now(),
				Conclusion:  RunConclusion_SUCCEEDED,
			},
		},
		Annotations: []*Annotation{
			{
				AnnotationLevel: AnnotationLevel_LEVEL_NOTICE,
				Message:         "message",
				RawDetails:      "raw details",
				Path:            "path",
				StartLine:       2,
				EndLine:         2,
				StartColumn:     1,
				EndColumn:       5,
				StepNumber:      3,
				Title:           "title",
			},
		},
	}

	err := gqls.client.UpdateCheckSuite(context.Background(), &rsr, UpdateCheckSuiteParams{CheckSuiteState: &testCheckSuiteState, WaitingOn: &waitingOn})
	gqls.NoError(err)
	_ = gqls.ghClient.AssertExpectations(gqls.T())
}

func (gqls *gqlStatusServiceSuite) Test_RunStatus_Concurrency() {
	waitingOn := WaitingOn{
		CheckSuiteID: testWaitingOnCheckSuiteID,
	}

	gqls.ghClient.On(
		"UpdateCheckSuite",
		mock.Anything,
		github.UpdateCheckSuiteRequest{
			RepositoryID: testRepositoryID,
			CheckSuiteID: testCheckSuiteID,
			Artifacts:    []*github.CheckRunArtifact{},
			Concurrency: &github.Concurrency{
				Group: "testGroup",
				WaitingOnResource: &github.WaitingOnResource{
					CheckSuiteID: testWaitingOnCheckSuiteID,
					CheckRunID:   "",
				},
			},
		},
	).Return(&types.IDPair{}, nil).Once()

	rsr := RunStatusRequest{
		WorkflowId: testWorkflowID,
		Progress: &RunStatusRequest_NotStarted{
			NotStarted: &RunNotStarted{
				Status: RunStatus_PENDING,
			},
		},
		Concurrency: &Concurrency{
			Group: "testGroup",
			WaitingOnResource: &WaitingOnResource{
				RunExternalId: "some-concurrency-run-external-id",
				JobExternalId: "",
			},
		},
	}

	err := gqls.client.UpdateCheckSuite(context.Background(), &rsr, UpdateCheckSuiteParams{CheckSuiteState: &testCheckSuiteState, WaitingOn: &waitingOn})
	gqls.NoError(err)
	_ = gqls.ghClient.AssertExpectations(gqls.T())
}

func (gqls *gqlStatusServiceSuite) Test_RunStatus_Concurrency_WaitingOnCalledJob() {
	waitingOn := WaitingOn{
		CheckSuiteID: testWaitingOnCheckSuiteID,
	}

	gqls.ghClient.On(
		"UpdateCheckSuite",
		mock.Anything,
		github.UpdateCheckSuiteRequest{
			RepositoryID: testRepositoryID,
			CheckSuiteID: testCheckSuiteID,
			Artifacts:    []*github.CheckRunArtifact{},
			Concurrency: &github.Concurrency{
				Group: "testGroup",
				WaitingOnResource: &github.WaitingOnResource{
					CheckSuiteID: testWaitingOnCheckSuiteID,
					CheckRunID:   "",
					Identifier:   "test",
				},
			},
		},
	).Return(&types.IDPair{}, nil).Once()

	rsr := RunStatusRequest{
		WorkflowId: testWorkflowID,
		Progress: &RunStatusRequest_NotStarted{
			NotStarted: &RunNotStarted{
				Status: RunStatus_PENDING,
			},
		},
		Concurrency: &Concurrency{
			Group: "testGroup",
			WaitingOnResource: &WaitingOnResource{
				RunExternalId: "7932bae7-53d0-4c3a-a367-6796ce577dba",
				JobExternalId: "",
				Identifier:    "test",
			},
		},
	}

	err := gqls.client.UpdateCheckSuite(context.Background(), &rsr, UpdateCheckSuiteParams{CheckSuiteState: &testCheckSuiteState, WaitingOn: &waitingOn})
	gqls.NoError(err)
	_ = gqls.ghClient.AssertExpectations(gqls.T())
}

func (gqls *gqlStatusServiceSuite) Test_RunStatus_Concurrency_NoWaitingOn() {
	waitingOn := WaitingOn{}

	gqls.ghClient.On(
		"UpdateCheckSuite",
		mock.Anything,
		github.UpdateCheckSuiteRequest{
			RepositoryID: testRepositoryID,
			CheckSuiteID: testCheckSuiteID,
			Artifacts:    []*github.CheckRunArtifact{},
			Concurrency: &github.Concurrency{
				Group: "testGroup",
			},
		},
	).Return(&types.IDPair{}, nil).Once()

	rsr := RunStatusRequest{
		WorkflowId: testWorkflowID,
		Progress: &RunStatusRequest_NotStarted{
			NotStarted: &RunNotStarted{
				Status: RunStatus_PENDING,
			},
		},
		Concurrency: &Concurrency{
			Group: "testGroup",
		},
	}

	err := gqls.client.UpdateCheckSuite(context.Background(), &rsr, UpdateCheckSuiteParams{CheckSuiteState: &testCheckSuiteState, WaitingOn: &waitingOn})
	gqls.NoError(err)
	_ = gqls.ghClient.AssertExpectations(gqls.T())
}

func (gqls *gqlStatusServiceSuite) Test_UpdateGateStatus_GraphQL() {
	testExternalID := "ceebd9fd-33aa-598a-caef-2b563f1c65c7"
	testToken := "1234"

	expiresAt := time.Now().Add(-1 * time.Hour).UTC()

	gqls.ghClient.On(
		"CreateGateRequest",
		mock.Anything,
		github.CreateGateRequestRequest{
			GateID:     testGateID,
			CheckRunID: testCheckRunID,
			State:      "CLOSED",
			Token:      testToken,
			Concluded:  false,
			ExpiresAt:  expiresAt,
		},
	).Return(&types.IDPair{}, nil).Once()

	gqls.ghClientFactory.ExpectedCalls = []*mock.Call{} // reset mocks
	gqls.ghClientFactory.
		On("NewClientForRepositoryOwner",
			mock.Anything,
			testRepoGlobalID,
			mock.Anything,
		).Return(gqls.ghClient, nil)

	expiresAtProto := timestamppb.New(expiresAt)
	err := gqls.client.UpdateGateStatus(context.Background(), &GateStatusRequest{
		GateId:      testGateID.String(),
		ExternalId:  testExternalID,
		IsOpen:      false,
		Type:        "remote",
		Token:       testToken,
		IsConcluded: false,
		Deadline:    expiresAtProto,
	}, UpdateGateStatusParams{CheckRunID: testCheckRunID, RepositoryID: testRepoGlobalID})

	gqls.NoError(err)
	gqls.ghClient.AssertExpectations(gqls.T())
	gqls.ghClientFactory.AssertExpectations(gqls.T())
}

func (gqls *gqlStatusServiceSuite) Test_UpdateGateStatus_GraphQLNotFound() {
	testExternalID := "ceebd9fd-33aa-598a-caef-2b563f1c65c7"
	testToken := "1234"
	gqlError := errors.NewGraphQLError(errors.NewNotFoundError(errs.New("Not Found")))

	gqls.ghClient.On(
		"CreateGateRequest",
		mock.Anything,
		github.CreateGateRequestRequest{
			GateID:     testGateID,
			CheckRunID: testCheckRunID,
			State:      "CLOSED",
			Token:      testToken,
			Concluded:  false,
		},
	).Return(&types.IDPair{}, gqlError).Once()

	err := gqls.client.UpdateGateStatus(context.Background(), &GateStatusRequest{
		GateId:      testGateID.String(),
		ExternalId:  testExternalID,
		IsOpen:      false,
		Type:        "remote",
		Token:       testToken,
		IsConcluded: false,
	}, UpdateGateStatusParams{CheckRunID: testCheckRunID, OwnerID: testOrgGlobalID, RepositoryID: testRepoGlobalID})

	gqls.ErrorIs(err, gqlError)
}

func (gqls *gqlStatusServiceSuite) Test_Multitenant_Valid_ID() {
	startedAt, startedAtProto, _, _ := gqls.getTimings()
	waitingOn := WaitingOn{}
	githubTenantID := int64(4)
	gqls.client.isMultitenant = true

	// clear default mocks for WorkflowBuildsRepository
	gqls.wfbRepo.ExpectedCalls = []*mock.Call{}

	gqls.wfbRepo.On(
		"GetDataForTokenRequest",
		mock.Anything,
		testWorkflowID,
	).Return(&deployer.DataForTokenRequest{
		TokenPermissions: &tokens.PermissionSettings{
			InstallationPermissions: *tokens.NewInstallationPermissions(tokens.WritePermissions),
			DefaultPermissions:      tokens.WritePermissions,
		},
		RepositoryID:     testRepoGlobalID,
		GitHubTenantID:   &githubTenantID,
		WorkflowMetadata: &metadata.WorkflowMetadata{},
	}, true, nil)

	gqls.ghClient.On(
		"CreateCheckRun",
		mock.Anything,
		github.CreateCheckRunRequest{
			RepositoryID: testRepositoryID,
			CheckSuiteID: testCheckSuiteID,
			ExternalID:   testExternalID,
			HeadSHA:      testCommitSHA,
			Name:         testJobIDA,
			DisplayName:  testJobNameA,
			Number:       1,
			Status:       "IN_PROGRESS",
			StartedAt:    startedAt,
			CompletedLog: &github.CompletedLog{
				URL:   testJobLogsURL,
				Lines: 1,
			},
			Steps: []github.CheckStepData{
				{
					ExternalID:   "some-step-external-id",
					Name:         "some-step-name",
					Number:       456,
					StartedAt:    startedAt,
					Status:       "IN_PROGRESS",
					CompletedLog: nil,
					CompletedAt:  nil,
					Conclusion:   "",
				},
			},
		},
	).Return(
		testCheckRunResponse,
		nil,
	)

	jsr := JobStatusRequest{
		WorkflowId:  testWorkflowID,
		JobId:       testJobIDA,
		ExternalId:  testExternalID,
		DisplayName: testJobNameA,
		Number:      1,
		Progress: &JobStatusRequest_InProgress{
			InProgress: &JobInProgress{
				Status:    Status_STATUS_IN_PROGRESS,
				StartedAt: startedAtProto,
				Log: &Log{
					Url:       testJobLogsURL,
					Lines:     1,
					CreatedAt: startedAtProto,
				},
			},
		},
		Steps: []*JobStep{
			{
				ExternalId: "some-step-external-id",
				Name:       "some-step-name",
				Number:     456,
				Progress: &JobStep_InProgress{
					InProgress: &StepInProgress{
						Status:    Status_STATUS_IN_PROGRESS,
						StartedAt: startedAtProto,
					},
				},
			},
		},
	}

	idPair, err := gqls.client.CreateCheckRun(context.Background(), &jsr, CreateCheckRunParams{CheckSuiteState: &testCheckSuiteState, WaitingOn: &waitingOn})
	gqls.NoError(err)
	gqls.Equal(testCheckRunID, idPair.GlobalID)
	_ = gqls.ghClient.AssertExpectations(gqls.T())
}

func (gqls *gqlStatusServiceSuite) Test_Multitenant_Invalid_ID() {
	_, startedAtProto, _, _ := gqls.getTimings()
	waitingOn := WaitingOn{}
	githubTenantID := int64(-1)
	gqls.client.isMultitenant = true

	// clear default mocks
	gqls.wfbRepo.ExpectedCalls = []*mock.Call{}
	gqls.ghClientFactory.ExpectedCalls = []*mock.Call{}

	gqls.wfbRepo.On(
		"GetDataForTokenRequest",
		mock.Anything,
		testWorkflowID,
	).Return(&deployer.DataForTokenRequest{
		TokenPermissions: &tokens.PermissionSettings{
			InstallationPermissions: *tokens.NewInstallationPermissions(tokens.WritePermissions),
			DefaultPermissions:      tokens.WritePermissions,
		},
		RepositoryID:   testRepoGlobalID,
		GitHubTenantID: &githubTenantID,
	}, true, nil)

	jsr := JobStatusRequest{
		WorkflowId:  testWorkflowID,
		JobId:       testJobIDA,
		ExternalId:  testExternalID,
		DisplayName: testJobNameA,
		Number:      1,
		Progress: &JobStatusRequest_InProgress{
			InProgress: &JobInProgress{
				Status:    Status_STATUS_IN_PROGRESS,
				StartedAt: startedAtProto,
				Log: &Log{
					Url:       testJobLogsURL,
					Lines:     1,
					CreatedAt: startedAtProto,
				},
			},
		},
		Steps: []*JobStep{
			{
				ExternalId: "some-step-external-id",
				Name:       "some-step-name",
				Number:     456,
				Progress: &JobStep_InProgress{
					InProgress: &StepInProgress{
						Status:    Status_STATUS_IN_PROGRESS,
						StartedAt: startedAtProto,
					},
				},
			},
		},
	}

	idPair, err := gqls.client.CreateCheckRun(context.Background(), &jsr, CreateCheckRunParams{CheckSuiteState: &testCheckSuiteState, WaitingOn: &waitingOn})
	gqls.Error(err)
	gqls.Nil(idPair)
	_ = gqls.ghClient.AssertExpectations(gqls.T())
}

func (gqls *gqlStatusServiceSuite) Test_Multitenant_Nil_ID() {
	_, startedAtProto, _, _ := gqls.getTimings()
	waitingOn := WaitingOn{}
	gqls.client.isMultitenant = true

	// clear default mocks
	gqls.wfbRepo.ExpectedCalls = []*mock.Call{}
	gqls.ghClientFactory.ExpectedCalls = []*mock.Call{}

	gqls.wfbRepo.On(
		"GetDataForTokenRequest",
		mock.Anything,
		testWorkflowID,
	).Return(&deployer.DataForTokenRequest{
		TokenPermissions: &tokens.PermissionSettings{
			InstallationPermissions: *tokens.NewInstallationPermissions(tokens.WritePermissions),
			DefaultPermissions:      tokens.WritePermissions,
		},
		RepositoryID:   testRepoGlobalID,
		GitHubTenantID: nil,
	}, true, nil)

	jsr := JobStatusRequest{
		WorkflowId:  testWorkflowID,
		JobId:       testJobIDA,
		ExternalId:  testExternalID,
		DisplayName: testJobNameA,
		Number:      1,
		Progress: &JobStatusRequest_InProgress{
			InProgress: &JobInProgress{
				Status:    Status_STATUS_IN_PROGRESS,
				StartedAt: startedAtProto,
				Log: &Log{
					Url:       testJobLogsURL,
					Lines:     1,
					CreatedAt: startedAtProto,
				},
			},
		},
		Steps: []*JobStep{
			{
				ExternalId: "some-step-external-id",
				Name:       "some-step-name",
				Number:     456,
				Progress: &JobStep_InProgress{
					InProgress: &StepInProgress{
						Status:    Status_STATUS_IN_PROGRESS,
						StartedAt: startedAtProto,
					},
				},
			},
		},
	}

	idPair, err := gqls.client.CreateCheckRun(context.Background(), &jsr, CreateCheckRunParams{CheckSuiteState: &testCheckSuiteState, WaitingOn: &waitingOn})
	gqls.Error(err)
	gqls.Nil(idPair)
	_ = gqls.ghClient.AssertExpectations(gqls.T())
}
