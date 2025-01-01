package status

import (
	"context"
	"testing"
	"time"

	"github.com/github/launch/clients/aqueduct"
	svcerr "github.com/github/launch/services/errors"
	"github.com/github/launch/types/errors"

	"github.com/github/launch/workflowbuild/azp/azptypes"

	errs "github.com/pkg/errors"
	"google.golang.org/protobuf/types/known/timestamppb"

	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/suite"

	"github.com/github/launch/clients/ghtwirp"
	"github.com/github/launch/clients/github"
	"github.com/github/launch/clients/github/tokens"
	"github.com/github/launch/clients/hydro/metadata"
	"github.com/github/launch/db/stores/deployer"
	hydroV0 "github.com/github/launch/hydro/schemas/github/actions/v0"
	entities "github.com/github/launch/hydro/schemas/github/v1/entities"
	"github.com/github/launch/observability/logger"
	"github.com/github/launch/observability/statter"
	"github.com/github/launch/pkg/azp"
	"github.com/github/launch/pkg/launchconfig"
	"github.com/github/launch/types"
	"github.com/github/launch/utils/graphqlid"
	"github.com/github/launch/utils/testutils"
	"github.com/github/launch/workflowbuild/build"
)

const (
	testWorkflowBuildDbID          = int64(234)
	testWorkflowID                 = "cbc57c67-bb6a-43f9-b5c6-5e313a991e5d"
	testJobIDA                     = "37b4edc4-6a90-49a3-943f-ab4a3fd4f0fd"
	testExternalID                 = "some-external-id"
	testCommitSHA                  = types.CommitSha("commitSHA")
	testJobNameA                   = "Build A"
	testJobNumberA                 = int64(42)
	testJobNameB                   = "build B"
	testJobLogsURL                 = "https://example.org/log.txt"
	testUserID                     = 10244
	testWorkflowFile               = ".github/workflows/main.yml"
	testJobDBID                    = int64(20142)
	testWorkflowBuildExecutionDbID = int64(567)
	testRunnerID                   = int64(999)
	testRunnerName                 = "my-runner-name"
	testRunnerGroupID              = int64(123)
	testRunnerGroupName            = "my-runner-group"
	testWaitingOnWorkflowBuildDbID = int64(876)
	testWorkflowRunAttempt         = int64(1)
)

var (
	testCheckRunID            = types.GlobalID(testutils.EncodeGlobalID("CheckRun", 3047))
	testCheckSuiteID          = types.GlobalID(testutils.EncodeGlobalID("CheckSuite", 1))
	testRepositoryID          = types.GlobalID(testutils.EncodeGlobalID("Repository", 3))
	testGateID                = types.GlobalID(testutils.EncodeGlobalID("Gate", 4))
	testWaitingOnCheckRunID   = types.GlobalID(testutils.EncodeGlobalID("CheckRun", 1088))
	testWaitingOnCheckSuiteID = types.GlobalID(testutils.EncodeGlobalID("CheckSuite", 18))
	testQueuedAt              = time.Now()
	testStartedAt             = time.Date(2000, 1, 1, 10, 0, 0, 1, time.UTC)
	testStartedAtProto        = timestamppb.New(testStartedAt)
	testCompletedAt           = testStartedAt.Add(time.Second * 10)
	testCompletedAtProto      = timestamppb.New(testCompletedAt)
	testCheckRunIDPair        = types.IDPair{GlobalID: testCheckRunID}
	testCheckSuiteIDPair      = types.IDPair{GlobalID: testCheckSuiteID}
	testCheckRunResponse      = github.CheckRunResponse{
		CheckSuiteIDPair: testCheckSuiteIDPair,
		CheckRunIDPair:   testCheckRunIDPair,
	}
	testCheckSuiteState = types.CheckSuiteState{
		RepositoryID:     testRepositoryID,
		EventSHA:         testCommitSHA,
		FlowIdentifier:   "A Workflow",
		WorkflowFilePath: testWorkflowFile,
		CheckSuiteIDPair: testCheckSuiteIDPair,
	}
)

func TestStatusService(t *testing.T) {
	suite.Run(t, new(statusServiceSuite))
}

type statusServiceSuite struct {
	suite.Suite

	azpResourcesRepo *deployer.MockAzpResourcesRepository
	ghClient         *github.MockClient
	wfbRepo          *deployer.MockWorkflowBuildsRepository
	jobRepo          *deployer.MockJobsRepository
	statusClient     *mockStatusClient
	syncStatusClient *mockSyncStatusClient
	usageClient      *mockUsageClient
	aqueductClient   *aqueduct.MockClient

	svc               *service
	hydro             *recordingEmitter
	ghClientFactory   *github.MockClientFactory
	githubTwirpClient *ghtwirp.MockClient
}

type recordingEmitter struct {
	workflowEvents       []*hydroV0.WorkflowExecution
	jobEvents            []*hydroV0.JobExecution
	workflowUpdateEvents []*hydroV0.WorkflowUpdate
	erroredEvents        []string
}

var _ Hydro = (*recordingEmitter)(nil)

func (r *recordingEmitter) EmitWorkflowExecution(event *hydroV0.WorkflowExecution) {
	r.workflowEvents = append(r.workflowEvents, event)
}

func (r *recordingEmitter) EmitJobExecution(event *hydroV0.JobExecution) {
	r.jobEvents = append(r.jobEvents, event)
}

func (r *recordingEmitter) EmitWorkflowUpdateEvent(_ context.Context, event *hydroV0.WorkflowUpdate) error {
	r.workflowUpdateEvents = append(r.workflowUpdateEvents, event)

	return nil
}

func (r *recordingEmitter) CountErroredEvent(eventType string) {
	r.erroredEvents = append(r.erroredEvents, eventType)
}

func (s *statusServiceSuite) SetupSubTest() {
	s.SetupTest()
}

func (s *statusServiceSuite) SetupTest() {
	s.azpResourcesRepo = deployer.NewMockAzpResourcesRepository(s.T())
	s.wfbRepo = deployer.NewMockWorkflowBuildsRepository(s.T())
	s.jobRepo = deployer.NewMockJobsRepository(s.T())
	s.ghClient = github.NewMockClient(s.T())
	s.githubTwirpClient = ghtwirp.NewMockClient(s.T())
	s.aqueductClient = aqueduct.NewMockClient(s.T())
	s.githubTwirpClient.EXPECT().IsRepositoryActionsDisabled(mock.Anything, mock.Anything).Return(false, nil).Maybe()
	s.githubTwirpClient.EXPECT().IsFeatureEnabledForRepoOrOwners(mock.Anything, mock.Anything, mock.Anything).Return(false).Maybe()

	s.ghClientFactory = github.NewMockClientFactory()
	azpClientFactory := azp.NewMockRepositoryClientFactory(s.T())
	addressableId := testWorkflowBuildExecutionDbID
	addressableWorkflowRunAttemptNumber := testWorkflowRunAttempt

	s.azpResourcesRepo.EXPECT().
		TryGet(mock.Anything, testRepositoryID).
		Return(&azptypes.BackingResources{
			CreationResult: azptypes.CreationResult{TenantID: testRepositoryID.String()},
			CreatedAt:      &testQueuedAt,
		}, nil).Maybe()

	s.wfbRepo.EXPECT().
		GetDataForStatusPostback(
			mock.Anything,
			testWorkflowID,
		).Return(
		&deployer.DataForStatusPostback{
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
			CreatedAt: testQueuedAt,
			QueuedAt:  &testQueuedAt,
			StartedAt: &testQueuedAt,
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
			WorkflowBuildExecutionDatabaseID: &addressableId,
			Attempt:                          &addressableWorkflowRunAttemptNumber,
		},
		true,
		nil,
	).Maybe()
	s.wfbRepo.EXPECT().
		GetDataForTokenRequest(
			mock.Anything,
			testWorkflowID,
		).Return(&deployer.DataForTokenRequest{
		TokenPermissions: &tokens.PermissionSettings{
			InstallationPermissions: *tokens.NewInstallationPermissions(tokens.WritePermissions),
			DefaultPermissions:      tokens.WritePermissions,
		},
	}, true, nil).Maybe()
	s.jobRepo.EXPECT().
		CreateWorkflowJob(
			mock.Anything,
			testWorkflowBuildDbID,
			testWorkflowID,
			testJobIDA,
			testCheckRunResponse.CheckRunIDPair.GlobalID,
			&addressableId).
		Return(testJobDBID, nil).
		Maybe()

	s.wfbRepo.EXPECT().SetWasDelayed(mock.Anything, mock.Anything).Return(nil).Maybe()

	s.wfbRepo.EXPECT().
		TransitionTo(
			mock.Anything,
			mock.Anything,
			mock.Anything,
		).Return(true, nil).Maybe()

	s.hydro = &recordingEmitter{}
	s.svc = New(logger.TestLogger(), statter.NullStatter(), s.azpResourcesRepo, s.wfbRepo, s.jobRepo, s.ghClientFactory, s.githubTwirpClient, azpClientFactory, false, s.hydro, nil, "test", false)

	s.statusClient = &mockStatusClient{}
	s.syncStatusClient = &mockSyncStatusClient{}
	s.usageClient = &mockUsageClient{}

	s.svc.aqueductClient = s.aqueductClient

	s.svc.makeStatusClient = func(ctx context.Context, svc *service, repoConfig *repoConfig) statusClient {
		return s.statusClient
	}
	s.svc.makeSyncStatusClient = func(ctx context.Context, svc *service, repositoryID types.GlobalID, workflowID string) syncStatusClient {
		return s.syncStatusClient
	}

	s.svc.makeUsageClient = func(ctx context.Context, svc *service) usageClient {
		return s.usageClient
	}
}

func (s *statusServiceSuite) TestMakeUsageClient() {
	cases := []struct {
		name     string
		setup    func(t *testing.T)
		expected usageClient
	}{
		{
			name:     "uses results client",
			expected: &resultsUsageClient{},
		},
		{
			name: "uses hydro client for enterprise",
			setup: func(t *testing.T) {
				testutils.SetAppMode(t, launchconfig.EnterpriseAppMode)
			},
			expected: &hydroUsageClient{},
		},
	}

	for _, c := range cases {
		s.Run(c.name, func() {
			if c.setup != nil {
				c.setup(s.T())
			}
			usageClient := makeUsageClient(context.TODO(), s.svc)
			s.IsType(c.expected, usageClient)
		})
	}
}

func (s *statusServiceSuite) TestMakeStatusClient() {
	testRepoConfig := &repoConfig{workflowID: testWorkflowID, buildRepo: s.svc.buildRepo}

	cases := []struct {
		name     string
		setup    func(t *testing.T)
		expected statusClient
	}{
		{
			name:     "uses results client",
			expected: &resultsStatusClient{},
		},
		{
			name: "uses graphql client for enterprise",
			setup: func(t *testing.T) {
				testutils.SetAppMode(t, launchconfig.EnterpriseAppMode)
			},
			expected: &graphQLStatusClient{},
		},
	}

	for _, c := range cases {
		s.Run(c.name, func() {
			if c.setup != nil {
				c.setup(s.T())
			}
			statusClient := makeStatusClient(context.TODO(), s.svc, testRepoConfig)
			s.IsType(c.expected, statusClient)
		})
	}

	// additionally, we should always use graphql for sync calls
	syncClient := makeSyncStatusClient(context.Background(), s.svc, testRepositoryID, testWorkflowID)
	s.IsType(syncClient, &graphQLStatusClient{})
}

func (s *statusServiceSuite) Test_InProgressJob_CreatesExpectedCheckRun() {
	testutils.SetAppMode(s.T(), launchconfig.EnterpriseAppMode)

	s.jobRepo.EXPECT().
		GetWorkflowJobFromJobID(mock.Anything, testWorkflowID, testJobIDA).
		Return(nil, nil)

	jsr := JobStatusRequest{
		WorkflowId:  testWorkflowID,
		JobId:       testJobIDA,
		ExternalId:  testExternalID,
		DisplayName: testJobNameA,
		Number:      1,
		Progress: &JobStatusRequest_InProgress{
			InProgress: &JobInProgress{
				Status:    Status_STATUS_IN_PROGRESS,
				StartedAt: testStartedAtProto,
				Log: &Log{
					Url:       testJobLogsURL,
					Lines:     1,
					CreatedAt: testStartedAtProto,
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
						StartedAt: testStartedAtProto,
					},
				},
			},
		},
	}

	s.syncStatusClient.EXPECT().
		CreateCheckRun(
			mock.Anything,
			&jsr,
			CreateCheckRunParams{
				CheckSuiteState: &testCheckSuiteState,
				WaitingOn:       &WaitingOn{},
			},
		).Return(&testCheckRunIDPair, nil).Once()

	_, err := s.svc.JobStatus(context.Background(), &jsr)

	s.NoError(err)
	s.Len(s.hydro.jobEvents, 0, "should not have emitted till complete")
}

func (s *statusServiceSuite) Test_InProgressJobWithLog_CreatesExpectedCheckRun() {
	testutils.SetAppMode(s.T(), launchconfig.EnterpriseAppMode)

	addressableId := testWorkflowBuildExecutionDbID

	s.jobRepo.EXPECT().
		GetWorkflowJobFromJobID(mock.Anything, testWorkflowID, testJobIDA).
		Return(nil, nil)

	s.jobRepo.EXPECT().
		CreateWorkflowJob(
			mock.Anything,
			testWorkflowBuildDbID,
			testWorkflowID,
			testJobIDA,
			testCheckRunResponse.CheckRunIDPair.GlobalID,
			&addressableId).
		Return(testJobDBID, nil)

	jsr := JobStatusRequest{
		WorkflowId:  testWorkflowID,
		JobId:       testJobIDA,
		ExternalId:  testExternalID,
		DisplayName: testJobNameA,
		Number:      1,
		Progress: &JobStatusRequest_InProgress{
			InProgress: &JobInProgress{
				Status:    Status_STATUS_IN_PROGRESS,
				StartedAt: testStartedAtProto,
				Log: &Log{
					Url:       testJobLogsURL,
					Lines:     1,
					CreatedAt: testStartedAtProto,
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
						StartedAt: testStartedAtProto,
					},
				},
			},
		},
	}

	s.syncStatusClient.EXPECT().
		CreateCheckRun(
			mock.Anything,
			&jsr,
			CreateCheckRunParams{
				CheckSuiteState: &testCheckSuiteState,
				WaitingOn:       &WaitingOn{},
			},
		).Return(&testCheckRunIDPair, nil).Once()

	s.wfbRepo.EXPECT().
		GetDataForStatusPostback(
			mock.Anything,
			testWorkflowID,
		).Return(
		&deployer.DataForStatusPostback{
			WorkflowBuildDatabaseID: testWorkflowBuildDbID,
		},
		true,
		nil,
	)
	_, err := s.svc.JobStatus(context.Background(), &jsr)

	s.NoError(err)
	s.Len(s.hydro.jobEvents, 0, "should not have emitted till complete")
}

func (s *statusServiceSuite) Test_EnvironmentWithName_CreatesExpectedCheckRun() {
	testutils.SetAppMode(s.T(), launchconfig.EnterpriseAppMode)

	s.jobRepo.EXPECT().
		GetWorkflowJobFromJobID(mock.Anything, testWorkflowID, testJobIDA).
		Return(nil, nil)

	jsr := JobStatusRequest{
		WorkflowId:  testWorkflowID,
		JobId:       testJobIDA,
		ExternalId:  testExternalID,
		DisplayName: testJobNameA,
		Number:      1,
		Progress: &JobStatusRequest_InProgress{
			InProgress: &JobInProgress{
				Status:    Status_STATUS_IN_PROGRESS,
				StartedAt: testStartedAtProto,
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
						StartedAt: testStartedAtProto,
					},
				},
			},
		},
		Environment: &Environment{
			Name: "staging",
		},
	}

	s.syncStatusClient.EXPECT().
		CreateCheckRun(
			mock.Anything,
			&jsr,
			CreateCheckRunParams{
				CheckSuiteState: &testCheckSuiteState,
				WaitingOn:       &WaitingOn{},
			},
		).Return(&testCheckRunIDPair, nil).Once()

	_, err := s.svc.JobStatus(context.Background(), &jsr)

	s.NoError(err)
	s.Len(s.hydro.jobEvents, 0, "should not have emitted till complete")
}

func (s *statusServiceSuite) Test_Concurrency_CreatesExpectedCheckRun() {
	testutils.SetAppMode(s.T(), launchconfig.EnterpriseAppMode)

	s.wfbRepo.EXPECT().
		GetWaitingOnResourceCheckRunID(
			mock.Anything,
			"7932bae7-53d0-4c3a-a367-6796ce577dba,3032fcfd-deae-56f7-b0ea-1caf60f8b58a",
		).Return(&deployer.DataForWaitingOnCheckRunResource{
		WorkflowJobCheckRunID:   testWaitingOnCheckRunID,
		WorkflowBuildDatabaseID: testWaitingOnWorkflowBuildDbID,
	}, true, nil)
	s.wfbRepo.EXPECT().SetWasDelayed(mock.Anything, testWorkflowBuildDbID).Return(nil)

	s.jobRepo.EXPECT().
		GetWorkflowJobFromJobID(mock.Anything, testWorkflowID, testJobIDA).
		Return(nil, nil)

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

	s.syncStatusClient.EXPECT().
		CreateCheckRun(
			mock.Anything,
			&jsr,
			CreateCheckRunParams{
				CheckSuiteState: &testCheckSuiteState,
				WaitingOn: &WaitingOn{
					CheckRunID: testWaitingOnCheckRunID,
				},
			},
		).Return(&testCheckRunIDPair, nil).Once()

	_, err := s.svc.JobStatus(context.Background(), &jsr)

	s.NoError(err)
	s.Len(s.hydro.jobEvents, 0, "should not have emitted till complete")
}

func (s *statusServiceSuite) Test_JobStatus_Concurrency_WaitingOnCalledJob() {
	testutils.SetAppMode(s.T(), launchconfig.EnterpriseAppMode)

	s.wfbRepo.EXPECT().
		GetWaitingOnResourceCheckRunID(
			mock.Anything,
			"7932bae7-53d0-4c3a-a367-6796ce577dba,3032fcfd-deae-56f7-b0ea-1caf60f8b58a",
		).Return(nil, false, nil)
	s.wfbRepo.EXPECT().
		GetWaitingOnResourceCheckSuiteID(
			mock.Anything,
			"7932bae7-53d0-4c3a-a367-6796ce577dba",
		).Return(&deployer.DataForWaitingOnCheckSuiteResource{
		WorkflowBuildCheckSuiteID: testWaitingOnCheckSuiteID,
		WorkflowBuildDatabaseID:   testWaitingOnWorkflowBuildDbID,
	}, true, nil)
	s.jobRepo.EXPECT().
		GetWorkflowJobFromJobID(mock.Anything, testWorkflowID, testJobIDA).
		Return(nil, nil)
	s.wfbRepo.EXPECT().SetWasDelayed(mock.Anything, testWorkflowBuildDbID).Return(nil)

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

	s.syncStatusClient.EXPECT().
		CreateCheckRun(
			mock.Anything,
			&jsr,
			CreateCheckRunParams{
				CheckSuiteState: &testCheckSuiteState,
				WaitingOn: &WaitingOn{
					CheckSuiteID: testWaitingOnCheckSuiteID,
				},
			},
		).Return(&testCheckRunIDPair, nil).Once()

	_, err := s.svc.JobStatus(context.Background(), &jsr)

	s.NoError(err)
	s.Len(s.hydro.jobEvents, 0, "should not have emitted till complete")
}

func (s *statusServiceSuite) Test_SuccessfulJobWithAnnotations_UpdatesExpectedCheckRun() {
	s.jobRepo.EXPECT().
		GetWorkflowJobFromJobID(mock.Anything, testWorkflowID, testJobIDA).
		Return(&deployer.WorkflowJob{
			ID:              testJobDBID,
			WorkflowBuildID: testWorkflowBuildDbID,
			ExternalJobID:   "external",
			CheckRunID:      testCheckRunResponse.CheckRunIDPair.GlobalID,
		}, nil)

	s.jobRepo.EXPECT().
		TouchWorkflowJob(
			mock.Anything,
			testJobDBID,
		).Return(nil).Once()

	jsr := JobStatusRequest{
		WorkflowId:  testWorkflowID,
		JobId:       testJobIDA,
		ExternalId:  testExternalID,
		DisplayName: testJobNameA,
		Number:      1,
		Progress: &JobStatusRequest_Complete{
			Complete: &JobComplete{
				Result:      Result_RESULT_SUCCEEDED,
				StartedAt:   testStartedAtProto,
				CompletedAt: testCompletedAtProto,
				Log: &Log{
					Url:       testJobLogsURL,
					Lines:     1,
					CreatedAt: testCompletedAtProto,
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
						StartedAt:   testStartedAtProto,
						CompletedAt: testCompletedAtProto,
						Log: &Log{
							Url:       "http://some-step-log.log",
							Lines:     2,
							CreatedAt: testCompletedAtProto,
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
				StartLine:       1,
				EndLine:         1,
				StartColumn:     1,
				EndColumn:       5,
				StepNumber:      3,
				Title:           "title",
			},
		},
	}

	s.statusClient.EXPECT().
		UpdateCheckRun(
			mock.Anything,
			&jsr,
			UpdateCheckRunParams{
				CheckSuiteState: &testCheckSuiteState,
				WaitingOn:       &WaitingOn{},
				CheckRunID:      testCheckRunID,
			},
		).Return(nil).Once()

	_, err := s.svc.JobStatus(context.Background(), &jsr)

	s.Require().NoError(err)
}

func (s *statusServiceSuite) Test_JobWithNilEnvironment_CreatesExpectedCheckRun() {
	s.jobRepo.EXPECT().
		GetWorkflowJobFromJobID(mock.Anything, testWorkflowID, testJobIDA).
		Return(&deployer.WorkflowJob{
			ID:              testJobDBID,
			WorkflowBuildID: testWorkflowBuildDbID,
			ExternalJobID:   "external",
			CheckRunID:      testCheckRunResponse.CheckRunIDPair.GlobalID,
		}, nil)

	s.jobRepo.EXPECT().
		TouchWorkflowJob(
			mock.Anything,
			testJobDBID,
		).Return(nil).Once()

	jsr := JobStatusRequest{
		WorkflowId:  testWorkflowID,
		JobId:       testJobIDA,
		ExternalId:  testExternalID,
		DisplayName: testJobNameA,
		Number:      1,
		Progress: &JobStatusRequest_InProgress{
			InProgress: &JobInProgress{
				Status:    Status_STATUS_IN_PROGRESS,
				StartedAt: testStartedAtProto,
			},
		},
		Environment: nil,
	}

	s.statusClient.EXPECT().
		UpdateCheckRun(
			mock.Anything,
			&jsr,
			UpdateCheckRunParams{
				CheckSuiteState: &testCheckSuiteState,
				WaitingOn:       &WaitingOn{},
				CheckRunID:      testCheckRunID,
			},
		).Return(nil).Once()

	_, err := s.svc.JobStatus(context.Background(), &jsr)

	s.Require().NoError(err)
}

func (s *statusServiceSuite) Test_JobWithEnvironmentName_CreatesExpectedCheckRun() {
	s.jobRepo.EXPECT().
		GetWorkflowJobFromJobID(mock.Anything, testWorkflowID, testJobIDA).
		Return(&deployer.WorkflowJob{
			ID:              testJobDBID,
			WorkflowBuildID: testWorkflowBuildDbID,
			ExternalJobID:   "external",
			CheckRunID:      testCheckRunResponse.CheckRunIDPair.GlobalID,
		}, nil)

	s.jobRepo.EXPECT().
		TouchWorkflowJob(
			mock.Anything,
			testJobDBID,
		).Return(nil).Once()

	jsr := JobStatusRequest{
		WorkflowId:  testWorkflowID,
		JobId:       testJobIDA,
		ExternalId:  testExternalID,
		DisplayName: testJobNameA,
		Number:      1,
		Progress: &JobStatusRequest_InProgress{
			InProgress: &JobInProgress{
				Status:    Status_STATUS_IN_PROGRESS,
				StartedAt: testStartedAtProto,
			},
		},
		Environment: &Environment{
			Name: "staging",
		},
	}

	s.statusClient.EXPECT().
		UpdateCheckRun(
			mock.Anything,
			&jsr,
			UpdateCheckRunParams{
				CheckSuiteState: &testCheckSuiteState,
				WaitingOn:       &WaitingOn{},
				CheckRunID:      testCheckRunID,
			},
		).Return(nil).Once()

	_, err := s.svc.JobStatus(context.Background(), &jsr)

	s.Require().NoError(err)
}

func (s *statusServiceSuite) Test_JobWithEnvironmentNameAndUrl_CreatesExpectedCheckRun() {
	s.jobRepo.EXPECT().
		GetWorkflowJobFromJobID(mock.Anything, testWorkflowID, testJobIDA).
		Return(&deployer.WorkflowJob{
			ID:              testJobDBID,
			WorkflowBuildID: testWorkflowBuildDbID,
			ExternalJobID:   "external",
			CheckRunID:      testCheckRunResponse.CheckRunIDPair.GlobalID,
		}, nil)

	s.jobRepo.EXPECT().
		TouchWorkflowJob(
			mock.Anything,
			testJobDBID,
		).Return(nil).Once()

	jsr := JobStatusRequest{
		WorkflowId:  testWorkflowID,
		JobId:       testJobIDA,
		ExternalId:  testExternalID,
		DisplayName: testJobNameA,
		Number:      1,
		Progress: &JobStatusRequest_InProgress{
			InProgress: &JobInProgress{
				Status:    Status_STATUS_IN_PROGRESS,
				StartedAt: testStartedAtProto,
			},
		},
		Environment: &Environment{
			Name: "staging",
			Url:  "http://github.com",
		},
	}

	s.statusClient.EXPECT().
		UpdateCheckRun(
			mock.Anything,
			&jsr,
			UpdateCheckRunParams{
				CheckSuiteState: &testCheckSuiteState,
				WaitingOn:       &WaitingOn{},
				CheckRunID:      testCheckRunID,
			},
		).Return(nil).Once()

	_, err := s.svc.JobStatus(context.Background(), &jsr)

	s.Require().NoError(err)
}

func (s *statusServiceSuite) Test_SuccessfulJobWithLogs_CreatesExpectedCheckRun() {
	billingChecked := true
	var checkRunID int64 = 3047

	s.jobRepo.EXPECT().
		GetWorkflowJobFromJobID(mock.Anything, testWorkflowID, testJobIDA).
		Return(&deployer.WorkflowJob{
			ID:              testJobDBID,
			WorkflowBuildID: testWorkflowBuildDbID,
			ExternalJobID:   "external",
			CheckRunID:      testCheckRunResponse.CheckRunIDPair.GlobalID,
			BillingChecked:  billingChecked,
		}, nil)

	s.jobRepo.EXPECT().
		TouchWorkflowJob(
			mock.Anything,
			testJobDBID,
		).Return(nil).Once()

	jsr := JobStatusRequest{
		WorkflowId:  testWorkflowID,
		JobId:       testJobIDA,
		ExternalId:  testExternalID,
		DisplayName: testJobNameA,
		Number:      1,
		Runtime:     "ubuntu",
		Progress: &JobStatusRequest_Complete{
			Complete: &JobComplete{
				Result:      Result_RESULT_SUCCEEDED,
				StartedAt:   testStartedAtProto,
				CompletedAt: testCompletedAtProto,
				Log: &Log{
					Url:       testJobLogsURL,
					Lines:     1,
					CreatedAt: testCompletedAtProto,
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
						StartedAt:   testStartedAtProto,
						CompletedAt: testCompletedAtProto,
						Log: &Log{
							Url:       "http://some-step-log.log",
							Lines:     2,
							CreatedAt: testCompletedAtProto,
						},
					},
				},
			},
		},
	}

	s.statusClient.EXPECT().
		UpdateCheckRun(
			mock.Anything,
			&jsr,
			UpdateCheckRunParams{
				CheckSuiteState: &testCheckSuiteState,
				WaitingOn:       &WaitingOn{},
				CheckRunID:      testCheckRunID,
			},
		).Return(nil).Once()

	s.usageClient.EXPECT().
		EmitUsage(
			mock.Anything,
			mock.Anything,
			testJobDBID,
			checkRunID,
			mock.Anything,
			mock.Anything,
			billingChecked,
		).Return(nil)

	_, err := s.svc.JobStatus(context.Background(), &jsr)

	s.Require().NoError(err)
}

func (s *statusServiceSuite) Test_CompletedSelfHostedJob_EmitsEvent() {
	billingChecked := true
	var checkRunId int64 = 3047

	s.jobRepo.EXPECT().
		GetWorkflowJobFromJobID(mock.Anything, testWorkflowID, testJobIDA).
		Return(&deployer.WorkflowJob{
			ID:              testJobDBID,
			WorkflowBuildID: testWorkflowBuildDbID,
			ExternalJobID:   "external",
			CheckRunID:      testCheckRunResponse.CheckRunIDPair.GlobalID,
			BillingChecked:  true,
		}, nil)

	s.jobRepo.EXPECT().
		TouchWorkflowJob(
			mock.Anything,
			testJobDBID,
		).Return(nil).Once()

	jsr := JobStatusRequest{
		WorkflowId:  testWorkflowID,
		JobId:       testJobIDA,
		ExternalId:  testExternalID,
		DisplayName: testJobNameA,
		Number:      1,
		Runtime:     "",
		SelfHosted:  true, // This is the important part. "" runtime + selfhosted = true.
		Progress: &JobStatusRequest_Complete{
			Complete: &JobComplete{
				Result:      Result_RESULT_SUCCEEDED,
				StartedAt:   testStartedAtProto,
				CompletedAt: testCompletedAtProto,
				Log: &Log{
					Url:       testJobLogsURL,
					Lines:     1,
					CreatedAt: testCompletedAtProto,
				},
			},
		},
	}

	s.statusClient.EXPECT().
		UpdateCheckRun(
			mock.Anything,
			&jsr,
			UpdateCheckRunParams{
				CheckSuiteState: &testCheckSuiteState,
				WaitingOn:       &WaitingOn{},
				CheckRunID:      testCheckRunID,
			},
		).Return(nil).Once()

	s.usageClient.EXPECT().
		EmitUsage(
			mock.Anything,
			mock.Anything,
			testJobDBID,
			checkRunId,
			mock.Anything,
			mock.Anything,
			billingChecked,
		).Return(nil)

	_, err := s.svc.JobStatus(context.Background(), &jsr)

	s.Require().NoError(err)
}

func (s *statusServiceSuite) Test_ClonedJob_DoesNotEmitEvent() {
	s.jobRepo.EXPECT().
		GetWorkflowJobFromJobID(mock.Anything, testWorkflowID, testJobIDA).
		Return(&deployer.WorkflowJob{
			ID:              testJobDBID,
			WorkflowBuildID: testWorkflowBuildDbID,
			ExternalJobID:   "external",
			CheckRunID:      testCheckRunResponse.CheckRunIDPair.GlobalID,
			BillingChecked:  true,
		}, nil)

	s.jobRepo.EXPECT().
		TouchWorkflowJob(
			mock.Anything,
			testJobDBID,
		).Return(nil).Once()

	jsr := JobStatusRequest{
		IsClonedFromPreviousRun: true,
		WorkflowId:              testWorkflowID,
		JobId:                   testJobIDA,
		ExternalId:              testExternalID,
		DisplayName:             testJobNameA,
		Number:                  1,
		Runtime:                 "ubuntu",
		Progress: &JobStatusRequest_Complete{
			Complete: &JobComplete{
				Result:      Result_RESULT_SUCCEEDED,
				StartedAt:   testStartedAtProto,
				CompletedAt: testCompletedAtProto,
				Log: &Log{
					Url:       testJobLogsURL,
					Lines:     1,
					CreatedAt: testCompletedAtProto,
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
						StartedAt:   testStartedAtProto,
						CompletedAt: testCompletedAtProto,
						Log: &Log{
							Url:       "http://some-step-log.log",
							Lines:     2,
							CreatedAt: testCompletedAtProto,
						},
					},
				},
			},
		},
	}

	s.statusClient.EXPECT().
		UpdateCheckRun(
			mock.Anything,
			&jsr,
			UpdateCheckRunParams{
				CheckSuiteState: &testCheckSuiteState,
				WaitingOn:       &WaitingOn{},
				CheckRunID:      testCheckRunID,
			},
		).Return(nil).Once()

	_, err := s.svc.JobStatus(context.Background(), &jsr)

	s.Require().NoError(err)
	s.Require().Len(s.hydro.jobEvents, 0)
}

func (s *statusServiceSuite) Test_SuccessfulJobWithoutLogs_CreatesExpectedCheckRun() {
	testutils.SetAppMode(s.T(), launchconfig.EnterpriseAppMode)

	s.jobRepo.EXPECT().
		GetWorkflowJobFromJobID(mock.Anything, testWorkflowID, testJobIDA).
		Return(nil, nil)

	jsr := JobStatusRequest{
		WorkflowId:  testWorkflowID,
		JobId:       testJobIDA,
		ExternalId:  testExternalID,
		DisplayName: testJobNameA,
		Number:      1,
		Progress: &JobStatusRequest_Complete{
			Complete: &JobComplete{
				Result:      Result_RESULT_SUCCEEDED,
				StartedAt:   testStartedAtProto,
				CompletedAt: testCompletedAtProto,
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
						StartedAt:   testStartedAtProto,
						CompletedAt: testCompletedAtProto,
						Log: &Log{
							Url:       "http://some-step-log.log",
							Lines:     2,
							CreatedAt: testCompletedAtProto,
						},
					},
				},
			},
		},
	}

	s.syncStatusClient.EXPECT().
		CreateCheckRun(
			mock.Anything,
			&jsr,
			CreateCheckRunParams{
				CheckSuiteState: &testCheckSuiteState,
				WaitingOn:       &WaitingOn{},
			},
		).Return(&testCheckRunIDPair, nil).Once()

	_, err := s.svc.JobStatus(context.Background(), &jsr)

	s.Require().NoError(err)
}

func (s *statusServiceSuite) Test_SuccessfulJob_CorrectlyUpdatesCheckRunWithLogs_IfCheckRunExists() {
	dbID := int64(987)
	s.jobRepo.EXPECT().
		GetWorkflowJobFromJobID(mock.Anything, testWorkflowID, testJobIDA).
		Return(&deployer.WorkflowJob{ID: dbID, CheckRunID: testCheckRunID}, nil)

	s.jobRepo.EXPECT().TouchWorkflowJob(mock.Anything, dbID).Return(nil)

	jsr := JobStatusRequest{
		WorkflowId:  testWorkflowID,
		DisplayName: testJobNameB,
		Number:      1,
		JobId:       testJobIDA,
		ExternalId:  testExternalID,
		Progress: &JobStatusRequest_Complete{
			Complete: &JobComplete{
				Result:      Result_RESULT_SUCCEEDED,
				StartedAt:   testStartedAtProto,
				CompletedAt: testCompletedAtProto,
				Log: &Log{
					Url:       testJobLogsURL,
					Lines:     1,
					CreatedAt: testCompletedAtProto,
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
						StartedAt:   testStartedAtProto,
						CompletedAt: testCompletedAtProto,
						Log: &Log{
							Url:       "http://some-step-log.log",
							Lines:     2,
							CreatedAt: testCompletedAtProto,
						},
					},
				},
			},
		},
	}

	s.statusClient.EXPECT().
		UpdateCheckRun(
			mock.Anything,
			&jsr,
			UpdateCheckRunParams{
				CheckSuiteState: &testCheckSuiteState,
				WaitingOn:       &WaitingOn{},
				CheckRunID:      testCheckRunID,
			},
		).Return(nil).Once()

	_, err := s.svc.JobStatus(context.Background(), &jsr)

	s.Require().NoError(err)
}

func (s *statusServiceSuite) Test_StartedJob_CorrectlyUpdatesCheckRunWithoutSettingStartedAgain() {
	dbID := int64(987)

	s.jobRepo.EXPECT().
		GetWorkflowJobFromJobID(mock.Anything, testWorkflowID, testJobIDA).
		Return(&deployer.WorkflowJob{ID: dbID, CheckRunID: testCheckRunID}, nil)

	s.jobRepo.EXPECT().TouchWorkflowJob(mock.Anything, dbID).Return(nil)

	jsr := JobStatusRequest{
		WorkflowId:  testWorkflowID,
		JobId:       testJobIDA,
		ExternalId:  testExternalID,
		DisplayName: testJobNameA,
		Number:      1,
		Progress: &JobStatusRequest_InProgress{
			InProgress: &JobInProgress{
				Status:    Status_STATUS_IN_PROGRESS,
				StartedAt: testStartedAtProto,
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
						StartedAt: testStartedAtProto,
					},
				},
			},
		},
	}

	s.statusClient.EXPECT().
		UpdateCheckRun(
			mock.Anything,
			&jsr,
			UpdateCheckRunParams{
				CheckSuiteState: &testCheckSuiteState,
				WaitingOn:       &WaitingOn{},
				CheckRunID:      testCheckRunID,
			},
		).Return(nil).Once()

	_, err := s.svc.JobStatus(context.Background(), &jsr)
	s.Require().NoError(err)

	s.jobRepo.EXPECT().
		GetWorkflowJobFromJobID(mock.Anything, testWorkflowID, testJobIDA).
		Return(&deployer.WorkflowJob{ID: dbID, CheckRunID: testCheckRunID}, nil)

	s.jobRepo.EXPECT().TouchWorkflowJob(mock.Anything, dbID).Return(nil)

	jsr = JobStatusRequest{
		WorkflowId:  testWorkflowID,
		DisplayName: testJobNameB,
		Number:      1,
		JobId:       testJobIDA,
		ExternalId:  testExternalID,
		Progress: &JobStatusRequest_Complete{
			Complete: &JobComplete{
				Result:      Result_RESULT_SUCCEEDED,
				StartedAt:   testStartedAtProto,
				CompletedAt: testCompletedAtProto,
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
						StartedAt:   testStartedAtProto,
						CompletedAt: testCompletedAtProto,
						Log: &Log{
							Url:       "http://some-step-log.log",
							Lines:     2,
							CreatedAt: testCompletedAtProto,
						},
					},
				},
			},
		},
	}

	s.statusClient.EXPECT().
		UpdateCheckRun(
			mock.Anything,
			&jsr,
			UpdateCheckRunParams{
				CheckSuiteState: &testCheckSuiteState,
				WaitingOn:       &WaitingOn{},
				CheckRunID:      testCheckRunID,
			},
		).Return(nil).Once()

	_, err = s.svc.JobStatus(context.Background(), &jsr)

	s.Require().NoError(err)
}

func (s *statusServiceSuite) Test_DelayedJob_SetsJobDelayedToTrue() {
	dbID := int64(987)

	s.jobRepo.EXPECT().
		GetWorkflowJobFromJobID(mock.Anything, testWorkflowID, testJobIDA).
		Return(&deployer.WorkflowJob{ID: dbID, CheckRunID: testCheckRunID}, nil)

	s.wfbRepo.EXPECT().SetWasDelayed(mock.Anything, testWorkflowBuildDbID).Return(nil)

	s.jobRepo.EXPECT().TouchWorkflowJob(mock.Anything, dbID).Return(nil)

	jsr := JobStatusRequest{
		WorkflowId:  testWorkflowID,
		JobId:       testJobIDA,
		ExternalId:  testExternalID,
		DisplayName: testJobNameA,
		Number:      1,
		Delayed:     true,
	}

	s.statusClient.EXPECT().
		UpdateCheckRun(
			mock.Anything,
			&jsr,
			UpdateCheckRunParams{
				CheckSuiteState: &testCheckSuiteState,
				WaitingOn:       &WaitingOn{},
				CheckRunID:      testCheckRunID,
			},
		).Return(nil).Once()

	_, err := s.svc.JobStatus(context.Background(), &jsr)

	s.Require().NoError(err)

	s.jobRepo.EXPECT().
		GetWorkflowJobFromJobID(mock.Anything, testWorkflowID, testJobIDA).
		Return(&deployer.WorkflowJob{ID: dbID, CheckRunID: testCheckRunID}, nil)

	s.jobRepo.EXPECT().TouchWorkflowJob(mock.Anything, dbID).Return(nil)

	jsr = JobStatusRequest{
		WorkflowId:  testWorkflowID,
		DisplayName: testJobNameB,
		Number:      1,
		JobId:       testJobIDA,
		ExternalId:  testExternalID,
		Progress: &JobStatusRequest_Complete{
			Complete: &JobComplete{
				Result:      Result_RESULT_SUCCEEDED,
				StartedAt:   testStartedAtProto,
				CompletedAt: testCompletedAtProto,
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
						StartedAt:   testStartedAtProto,
						CompletedAt: testCompletedAtProto,
						Log: &Log{
							Url:       "http://some-step-log.log",
							Lines:     2,
							CreatedAt: testCompletedAtProto,
						},
					},
				},
			},
		},
	}

	s.statusClient.EXPECT().
		UpdateCheckRun(
			mock.Anything,
			&jsr,
			UpdateCheckRunParams{
				CheckSuiteState: &testCheckSuiteState,
				WaitingOn:       &WaitingOn{},
				CheckRunID:      testCheckRunID,
			},
		).Return(nil).Once()

	_, err = s.svc.JobStatus(context.Background(), &jsr)

	s.Require().NoError(err)
}

func (s *statusServiceSuite) Test_SuccessfulJob_CorrectlyUpdatesCheckRunWithoutLogs_IfCheckRunExists() {
	dbID := int64(987)
	s.jobRepo.EXPECT().
		GetWorkflowJobFromJobID(mock.Anything, testWorkflowID, testJobIDA).
		Return(&deployer.WorkflowJob{ID: dbID, CheckRunID: testCheckRunID}, nil)

	s.jobRepo.EXPECT().TouchWorkflowJob(mock.Anything, dbID).Return(nil)

	jsr := JobStatusRequest{
		WorkflowId:  testWorkflowID,
		DisplayName: testJobNameB,
		Number:      1,
		JobId:       testJobIDA,
		ExternalId:  testExternalID,
		Progress: &JobStatusRequest_Complete{
			Complete: &JobComplete{
				Result:      Result_RESULT_SUCCEEDED,
				StartedAt:   testStartedAtProto,
				CompletedAt: testCompletedAtProto,
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
						StartedAt:   testStartedAtProto,
						CompletedAt: testCompletedAtProto,
						Log: &Log{
							Url:       "http://some-step-log.log",
							Lines:     2,
							CreatedAt: testCompletedAtProto,
						},
					},
				},
			},
		},
	}

	s.statusClient.EXPECT().
		UpdateCheckRun(
			mock.Anything,
			&jsr,
			UpdateCheckRunParams{
				CheckSuiteState: &testCheckSuiteState,
				WaitingOn:       &WaitingOn{},
				CheckRunID:      testCheckRunID,
			},
		).Return(nil).Once()

	_, err := s.svc.JobStatus(context.Background(), &jsr)

	s.Require().NoError(err)
}

func (s *statusServiceSuite) Test_SuccessfulJob_CorrectlyUpdatesCheckRunNoStartedAt_IfCheckRunExists() {
	dbID := int64(987)
	s.jobRepo.EXPECT().
		GetWorkflowJobFromJobID(mock.Anything, testWorkflowID, testJobIDA).
		Return(&deployer.WorkflowJob{ID: dbID, CheckRunID: testCheckRunID}, nil)
	s.jobRepo.EXPECT().TouchWorkflowJob(mock.Anything, dbID).Return(nil)

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
						StartedAt: testStartedAtProto,
					},
				},
			},
		},
	}

	s.statusClient.EXPECT().
		UpdateCheckRun(
			mock.Anything,
			&jsr,
			UpdateCheckRunParams{
				CheckSuiteState: &testCheckSuiteState,
				WaitingOn:       &WaitingOn{},
				CheckRunID:      testCheckRunID,
			},
		).Return(nil).Once()

	_, err := s.svc.JobStatus(context.Background(), &jsr)

	s.Require().NoError(err)
}

func (s *statusServiceSuite) Test_JobStatus_StatusClientNotFound() {
	dbID := int64(987)
	s.jobRepo.EXPECT().
		GetWorkflowJobFromJobID(mock.Anything, testWorkflowID, testJobIDA).
		Return(&deployer.WorkflowJob{ID: dbID, CheckRunID: testCheckRunID}, nil)

	s.statusClient.EXPECT().
		UpdateCheckRun(
			mock.Anything,
			mock.Anything,
			mock.Anything,
		).Return(errors.NewNotFoundError(errs.New("Not Found"))).Once()

	_, err := s.svc.JobStatus(context.Background(), &JobStatusRequest{
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
	})

	s.Equal(svcerr.NewNotFoundError("Check run or repository not found"), err)
}

func (s *statusServiceSuite) Test_CompletedRun_SkipsUpdateChecks() {
	s.wfbRepo.ExpectedCalls = nil
	s.wfbRepo.EXPECT().
		GetDataForStatusPostback(
			mock.Anything,
			testWorkflowID,
		).Return(
		&deployer.DataForStatusPostback{
			WorkflowBuildDatabaseID: testWorkflowBuildDbID,
			QueuedAt:                &testQueuedAt,
			StartedAt:               &testStartedAt,
			CompletedAt:             &testCompletedAt,
		},
		true,
		nil,
	)

	_, err := s.svc.JobStatus(context.Background(), &JobStatusRequest{
		WorkflowId:  testWorkflowID,
		JobId:       testJobIDA,
		ExternalId:  testExternalID,
		DisplayName: testJobNameA,
		Number:      1,
		Progress: &JobStatusRequest_Complete{
			Complete: &JobComplete{
				Result:      Result_RESULT_SUCCEEDED,
				StartedAt:   testStartedAtProto,
				CompletedAt: testCompletedAtProto,
			},
		},
	})

	s.Require().Error(err)
	s.Require().Equal(ErrPostbackDenied, err)
}

func (s *statusServiceSuite) Test_RunStatus() {
	queuedAtProto := timestamppb.New(testQueuedAt)
	testStartedAtProto := timestamppb.New(queuedAtProto.AsTime())
	testCompletedAtProto := timestamppb.New(testStartedAtProto.AsTime().Add(time.Minute))

	artifactsCreatedAt := timestamppb.Now()
	artifactsCreatedAtTime := artifactsCreatedAt.AsTime()

	artifactsExpiresAtTime := artifactsCreatedAtTime.Add(time.Hour * 24)
	artifactsExpiresAtTimeCalculated := getArtifactExpiration(artifactsCreatedAtTime, artifactsExpiresAtTime)
	artifactsExpiresAt := timestamppb.New(artifactsExpiresAtTimeCalculated)
	s.wfbRepo.EXPECT().Complete(mock.Anything, mock.Anything, mock.Anything, testWorkflowBuildDbID, build.WorkflowStateSucceeded).Return(nil)

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
				StartedAt:   testStartedAtProto,
				CompletedAt: testCompletedAtProto,
				Conclusion:  RunConclusion_SUCCEEDED,
			},
		},
	}

	s.statusClient.EXPECT().
		UpdateCheckSuite(
			mock.Anything,
			&rsr,
			UpdateCheckSuiteParams{
				CheckSuiteState: &testCheckSuiteState,
				WaitingOn:       &WaitingOn{},
			},
		).Return(nil).Once()

	_, err := s.svc.RunStatus(context.Background(), &rsr)

	s.Require().NoError(err)
	s.Require().Len(s.hydro.workflowEvents, 1)
	s.Equal(&hydroV0.WorkflowExecution{
		WorkflowStartTime:          queuedAtProto,
		WorkflowEndTime:            rsr.GetComplete().GetCompletedAt(),
		ExternalProvider:           hydroV0.WorkflowExecution_AZP,
		ExternalProviderReference:  "",
		InvokingUserId:             testUserID,
		WorkflowRepositoryGlobalId: "MDEwOlJlcG9zaXRvcnkz",
		WorkflowRepositoryOwnerId:  testUserID,
		WorkflowRepositorySha:      testCommitSHA.String(),
		WorkflowFilePath:           testWorkflowFile,
		WorkflowBuildId:            uint64(testWorkflowBuildDbID),
		WorkflowRepositoryId:       3,
		CheckSuiteGlobalId:         "MDEwOkNoZWNrU3VpdGUx",
		CheckSuiteConclusion:       2,
		QueuedAt:                   queuedAtProto,
		StartedAt:                  timestamppb.New(queuedAtProto.AsTime()),
		CompletedAt:                rsr.GetComplete().GetCompletedAt(),
		WorkflowName:               []byte("A Workflow"),
		Attempt:                    testWorkflowRunAttempt,
	}, s.hydro.workflowEvents[0])
}

func (s *statusServiceSuite) Test_RunStatus_EmitsCorrectExecutionConclusion() {
	queuedAtProto := timestamppb.Now()
	testStartedAtProto := timestamppb.New(queuedAtProto.AsTime())
	s.wfbRepo.EXPECT().Complete(mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(nil)

	cases := []struct {
		in   RunConclusion
		want entities.CheckSuiteConclusion
	}{
		{RunConclusion_NOT_PROVIDED, entities.CheckSuiteConclusion_UNKNOWN},
		{RunConclusion_CANCELED, entities.CheckSuiteConclusion_CANCELLED},
		{RunConclusion_FAILED, entities.CheckSuiteConclusion_FAILURE},
		{RunConclusion_SUCCEEDED, entities.CheckSuiteConclusion_SUCCESS},
		{RunConclusion_SKIPPED, entities.CheckSuiteConclusion_SKIPPED},
	}

	for _, tc := range cases {
		rsr := RunStatusRequest{
			WorkflowId: testWorkflowID,
			Progress: &RunStatusRequest_Complete{
				Complete: &RunComplete{
					StartedAt:   timestamppb.New(queuedAtProto.AsTime()),
					CompletedAt: timestamppb.New(testStartedAtProto.AsTime().Add(time.Minute)),
					Conclusion:  tc.in,
				},
			},
		}

		s.statusClient.EXPECT().
			UpdateCheckSuite(
				mock.Anything,
				&rsr,
				UpdateCheckSuiteParams{
					CheckSuiteState: &testCheckSuiteState,
					WaitingOn:       &WaitingOn{},
				},
			).Return(nil).Once()

		_, err := s.svc.RunStatus(context.Background(), &rsr)
		s.Require().NoError(err)
		s.Require().Len(s.hydro.workflowEvents, 1)
		s.Equal(tc.want, s.hydro.workflowEvents[0].CheckSuiteConclusion)
		s.hydro.workflowEvents = make([]*hydroV0.WorkflowExecution, 0)
	}
}

// as per https://github.com/github/launch/pull/2359 we want to ensure hydro events
// are emitted even if the repo is missing and we can't authenticate our GH client for it
func (s *statusServiceSuite) Test_RunStatus_EmitsWhenClientFails() {
	queuedAtProto := timestamppb.New(testQueuedAt)
	testStartedAtProto := timestamppb.New(queuedAtProto.AsTime())
	testCompletedAtProto := timestamppb.New(testStartedAtProto.AsTime().Add(time.Minute))

	artifactsCreatedAt := timestamppb.Now()
	artifactsExpiresAt := timestamppb.New(time.Now().Add(time.Hour * 24))

	s.statusClient.EXPECT().
		UpdateCheckSuite(
			mock.Anything,
			mock.Anything,
			mock.Anything,
		).Return(errs.New("fail")).Once()

	rsr := &RunStatusRequest{
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
				StartedAt:   testStartedAtProto,
				CompletedAt: testCompletedAtProto,
				Conclusion:  RunConclusion_SUCCEEDED,
			},
		},
	}
	_, err := s.svc.RunStatus(context.Background(), rsr)

	s.Require().Error(err)
	s.Require().Len(s.hydro.workflowEvents, 1)
	s.Equal(&hydroV0.WorkflowExecution{
		WorkflowStartTime:          queuedAtProto,
		WorkflowEndTime:            rsr.GetComplete().GetCompletedAt(),
		ExternalProvider:           hydroV0.WorkflowExecution_AZP,
		ExternalProviderReference:  "",
		InvokingUserId:             testUserID,
		WorkflowRepositoryGlobalId: "MDEwOlJlcG9zaXRvcnkz",
		WorkflowRepositoryOwnerId:  testUserID,
		WorkflowRepositorySha:      testCommitSHA.String(),
		WorkflowFilePath:           testWorkflowFile,
		WorkflowBuildId:            uint64(testWorkflowBuildDbID),
		WorkflowRepositoryId:       3,
		CheckSuiteGlobalId:         "MDEwOkNoZWNrU3VpdGUx",
		CheckSuiteConclusion:       2,
		QueuedAt:                   queuedAtProto,
		StartedAt:                  timestamppb.New(queuedAtProto.AsTime()),
		CompletedAt:                rsr.GetComplete().GetCompletedAt(),
		WorkflowName:               []byte("A Workflow"),
		Attempt:                    testWorkflowRunAttempt,
	}, s.hydro.workflowEvents[0])
}

func (s *statusServiceSuite) Test_RunStatus_Concurrency() {
	queuedAtProto := timestamppb.New(testQueuedAt)
	testStartedAtProto := timestamppb.New(queuedAtProto.AsTime())

	waitingForResource := &deployer.DataForWaitingOnCheckSuiteResource{
		WorkflowBuildCheckSuiteID: testWaitingOnCheckSuiteID,
		WorkflowBuildDatabaseID:   testWaitingOnWorkflowBuildDbID,
	}

	s.wfbRepo.EXPECT().
		GetWaitingOnResourceCheckSuiteID(
			mock.Anything,
			"some-concurrency-run-external-id",
		).Return(waitingForResource, true, nil)

	s.wfbRepo.EXPECT().SetWasDelayed(mock.Anything, testWorkflowBuildDbID).Return(nil)

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

	s.statusClient.EXPECT().
		UpdateCheckSuite(
			mock.Anything,
			&rsr,
			UpdateCheckSuiteParams{
				CheckSuiteState: &testCheckSuiteState,
				WaitingOn: &WaitingOn{
					CheckSuiteID: testWaitingOnCheckSuiteID,
				},
			},
		).Return(nil).Once()

	_, err := s.svc.RunStatus(context.Background(), &rsr)

	s.Require().NoError(err)
	s.Require().Len(s.hydro.workflowEvents, 1)
	s.Equal(&hydroV0.WorkflowExecution{
		WorkflowStartTime:          queuedAtProto,
		WorkflowEndTime:            nil,
		ExternalProvider:           hydroV0.WorkflowExecution_AZP,
		ExternalProviderReference:  "",
		InvokingUserId:             testUserID,
		WorkflowRepositoryGlobalId: "MDEwOlJlcG9zaXRvcnkz",
		WorkflowRepositoryOwnerId:  testUserID,
		WorkflowRepositorySha:      testCommitSHA.String(),
		WorkflowFilePath:           testWorkflowFile,
		WorkflowBuildId:            uint64(testWorkflowBuildDbID),
		WorkflowRepositoryId:       3,
		CheckSuiteGlobalId:         "MDEwOkNoZWNrU3VpdGUx",
		CheckSuiteConclusion:       0,
		QueuedAt:                   queuedAtProto,
		StartedAt:                  testStartedAtProto,
		CompletedAt:                nil,
		WorkflowName:               []byte("A Workflow"),
		Attempt:                    testWorkflowRunAttempt,
	}, s.hydro.workflowEvents[0])
}

func (s *statusServiceSuite) Test_RunStatus_Concurrency_WaitingOnCalledJob() {
	queuedAtProto := timestamppb.New(testQueuedAt)

	s.wfbRepo.EXPECT().
		GetWaitingOnResourceCheckRunID(
			mock.Anything,
			"7932bae7-53d0-4c3a-a367-6796ce577dba,3032fcfd-deae-56f7-b0ea-1caf60f8b58a",
		).Return(nil, false, nil).Maybe()
	s.wfbRepo.EXPECT().
		GetWaitingOnResourceCheckSuiteID(
			mock.Anything,
			"7932bae7-53d0-4c3a-a367-6796ce577dba",
		).Return(&deployer.DataForWaitingOnCheckSuiteResource{
		WorkflowBuildCheckSuiteID: testWaitingOnCheckSuiteID,
		WorkflowBuildDatabaseID:   testWaitingOnWorkflowBuildDbID,
	}, true, nil)

	s.wfbRepo.EXPECT().SetWasDelayed(mock.Anything, testWorkflowBuildDbID).Return(nil)

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

	s.statusClient.EXPECT().
		UpdateCheckSuite(
			mock.Anything,
			&rsr,
			UpdateCheckSuiteParams{
				CheckSuiteState: &testCheckSuiteState,
				WaitingOn: &WaitingOn{
					CheckSuiteID: testWaitingOnCheckSuiteID,
				},
			},
		).Return(nil).Once()

	_, err := s.svc.RunStatus(context.Background(), &rsr)

	s.Require().NoError(err)
	s.Require().Len(s.hydro.workflowEvents, 1)
	s.Equal(&hydroV0.WorkflowExecution{
		WorkflowStartTime:          queuedAtProto,
		WorkflowEndTime:            nil,
		ExternalProvider:           hydroV0.WorkflowExecution_AZP,
		ExternalProviderReference:  "",
		InvokingUserId:             testUserID,
		WorkflowRepositoryGlobalId: "MDEwOlJlcG9zaXRvcnkz",
		WorkflowRepositoryOwnerId:  testUserID,
		WorkflowRepositorySha:      testCommitSHA.String(),
		WorkflowFilePath:           testWorkflowFile,
		WorkflowBuildId:            uint64(testWorkflowBuildDbID),
		WorkflowRepositoryId:       3,
		CheckSuiteGlobalId:         "MDEwOkNoZWNrU3VpdGUx",
		CheckSuiteConclusion:       0,
		QueuedAt:                   queuedAtProto,
		StartedAt:                  timestamppb.New(queuedAtProto.AsTime()),
		CompletedAt:                nil,
		WorkflowName:               []byte("A Workflow"),
		Attempt:                    testWorkflowRunAttempt,
	}, s.hydro.workflowEvents[0])
}

func (s *statusServiceSuite) Test_RunStatus_Concurrency_NoWaitingOn() {
	queuedAtProto := timestamppb.New(testQueuedAt)

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

	s.statusClient.EXPECT().
		UpdateCheckSuite(
			mock.Anything,
			&rsr,
			UpdateCheckSuiteParams{
				CheckSuiteState: &testCheckSuiteState,
				WaitingOn:       &WaitingOn{},
			},
		).Return(nil).Once()

	_, err := s.svc.RunStatus(context.Background(), &rsr)

	s.Require().NoError(err)
	s.Require().Len(s.hydro.workflowEvents, 1)
	s.Equal(&hydroV0.WorkflowExecution{
		WorkflowStartTime:          queuedAtProto,
		WorkflowEndTime:            nil,
		ExternalProvider:           hydroV0.WorkflowExecution_AZP,
		ExternalProviderReference:  "",
		InvokingUserId:             testUserID,
		WorkflowRepositoryGlobalId: "MDEwOlJlcG9zaXRvcnkz",
		WorkflowRepositoryOwnerId:  testUserID,
		WorkflowRepositorySha:      testCommitSHA.String(),
		WorkflowFilePath:           testWorkflowFile,
		WorkflowBuildId:            uint64(testWorkflowBuildDbID),
		WorkflowRepositoryId:       3,
		CheckSuiteGlobalId:         "MDEwOkNoZWNrU3VpdGUx",
		CheckSuiteConclusion:       0,
		QueuedAt:                   queuedAtProto,
		StartedAt:                  timestamppb.New(queuedAtProto.AsTime()),
		CompletedAt:                nil,
		WorkflowName:               []byte("A Workflow"),
		Attempt:                    testWorkflowRunAttempt,
	}, s.hydro.workflowEvents[0])
}

func (s *statusServiceSuite) Test_GateStatus() {
	testExternalID := "ceebd9fd-33aa-598a-caef-2b563f1c65c7"
	testToken := "1234"

	// Clear the expected calls from the suite for this test
	s.wfbRepo.ExpectedCalls = []*mock.Call{}
	s.wfbRepo.EXPECT().
		GetDataForGatePostback(
			mock.Anything,
			testExternalID,
		).Return(
		&deployer.DataForGatePostback{
			WorkflowBuildDatabaseID: testWorkflowBuildDbID,
			CheckRunID:              testCheckRunID.String(),
			RepositoryID:            testRepositoryID,
			WasDelayed:              false,
		},
		true,
		nil,
	)

	s.wfbRepo.EXPECT().SetWasDelayed(mock.Anything, testWorkflowBuildDbID).Return(nil)

	expiresAt := time.Now().Add(-1 * time.Hour).UTC()
	expiresAtProto := timestamppb.New(expiresAt)
	gsr := GateStatusRequest{
		GateId:      testGateID.String(),
		ExternalId:  testExternalID,
		IsOpen:      false,
		Type:        "remote",
		Token:       testToken,
		IsConcluded: false,
		Deadline:    expiresAtProto,
	}

	s.statusClient.EXPECT().
		UpdateGateStatus(
			mock.Anything,
			&gsr,
			UpdateGateStatusParams{CheckRunID: types.GlobalID(testCheckRunID.String()), RepositoryID: testRepositoryID},
		).Return(nil).Once()

	_, err := s.svc.GateStatus(context.Background(), &gsr)

	s.Require().NoError(err)
}

func (s *statusServiceSuite) Test_SuccessfulJobWith_RunnerProperties() {
	s.jobRepo.EXPECT().
		GetWorkflowJobFromJobID(mock.Anything, testWorkflowID, testJobIDA).
		Return(&deployer.WorkflowJob{
			ID:              testJobDBID,
			WorkflowBuildID: testWorkflowBuildDbID,
			ExternalJobID:   "external",
			CheckRunID:      testCheckRunResponse.CheckRunIDPair.GlobalID,
		}, nil)

	s.jobRepo.EXPECT().
		TouchWorkflowJob(
			mock.Anything,
			testJobDBID,
		).Return(nil).Once()

	jsr := JobStatusRequest{
		WorkflowId:       testWorkflowID,
		JobId:            testJobIDA,
		ExternalId:       testExternalID,
		DisplayName:      testJobNameA,
		Number:           1,
		RunnerProperties: "{\"machine_size\":2,\"azure_sku\":\"Standard_D2_v3\"}",
		RunnerType:       "SELF_HOSTED",
		Progress: &JobStatusRequest_Complete{
			Complete: &JobComplete{
				Result:      Result_RESULT_SUCCEEDED,
				StartedAt:   testStartedAtProto,
				CompletedAt: testCompletedAtProto,
				Log: &Log{
					Url:       testJobLogsURL,
					Lines:     1,
					CreatedAt: testCompletedAtProto,
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
						StartedAt:   testStartedAtProto,
						CompletedAt: testCompletedAtProto,
						Log: &Log{
							Url:       "http://some-step-log.log",
							Lines:     2,
							CreatedAt: testCompletedAtProto,
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
				StartLine:       1,
				EndLine:         1,
				StartColumn:     1,
				EndColumn:       5,
				StepNumber:      3,
				Title:           "title",
			},
		},
	}

	s.statusClient.EXPECT().
		UpdateCheckRun(
			mock.Anything,
			&jsr,
			UpdateCheckRunParams{
				CheckSuiteState: &testCheckSuiteState,
				WaitingOn:       &WaitingOn{},
				CheckRunID:      testCheckRunID,
			},
		).Return(nil).Once()

	_, err := s.svc.JobStatus(context.Background(), &jsr)

	s.Require().NoError(err)
}

func (s *statusServiceSuite) Test_DeletedRepo_Canceled_JobStatus_EmitsHydroBillingMessage() {
	testutils.SetAppMode(s.T(), launchconfig.EnterpriseAppMode)
	fakeWorkflowCreatedTime := time.Now().UTC()
	fakeCreatedTimeForRestoredRepo := fakeWorkflowCreatedTime.Add(10 * time.Minute)
	cases := []struct {
		Name             string
		CheckSuiteIDPair types.IDPair
		AzpEntity        *azptypes.BackingResources
		AzpEntityGetErr  error
		WorkflowJob      *deployer.WorkflowJob
	}{
		{
			"restored with an existing job",
			types.IDPair{GlobalID: testCheckSuiteID},
			&azptypes.BackingResources{
				CreationResult: azptypes.CreationResult{TenantID: testRepositoryID.String()},
				CreatedAt:      &fakeCreatedTimeForRestoredRepo, /* treat this as restored repo */
			},
			nil,
			&deployer.WorkflowJob{ID: int64(987), CheckRunID: testCheckRunID},
		},
		{
			"deleted without a job",
			types.NilIDPair,
			nil,
			deployer.NewGetAzpResourcesError(testRepositoryID), /* NotFound means deleted repo */
			nil,
		},
	}

	for _, c := range cases {
		s.Run(c.CheckSuiteIDPair.GlobalID.String(), func() {
			s.azpResourcesRepo.ExpectedCalls = nil
			s.wfbRepo.ExpectedCalls = nil

			addressableId := testWorkflowBuildExecutionDbID

			s.wfbRepo.EXPECT().
				GetDataForStatusPostback(
					mock.Anything,
					testWorkflowID,
				).Return(
				&deployer.DataForStatusPostback{
					WorkflowBuildDatabaseID: testWorkflowBuildDbID,
					CheckSuiteState: &types.CheckSuiteState{
						RepositoryID:     testRepositoryID,
						EventSHA:         testCommitSHA,
						FlowIdentifier:   "A Workflow",
						WorkflowFilePath: testWorkflowFile,
						CheckSuiteIDPair: c.CheckSuiteIDPair,
					},
					CreatedAt: fakeWorkflowCreatedTime, // IMPORTANT for isRepoDeleted test
					QueuedAt:  &testQueuedAt,
					StartedAt: &testStartedAt,
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
					WorkflowBuildExecutionDatabaseID: &addressableId,
				},
				true,
				nil,
			)

			s.azpResourcesRepo.EXPECT().
				TryGet(mock.Anything, testRepositoryID).
				Return(c.AzpEntity, c.AzpEntityGetErr)

			s.jobRepo.EXPECT().
				GetWorkflowJobFromJobID(mock.Anything, testWorkflowID, testJobIDA).
				Return(c.WorkflowJob, nil)

			var (
				jobID      int64
				checkRunID int64
			)
			// for nil jobs, we expect zero-ed out jobID and checkRunID
			// otherwise, it should be published
			if c.WorkflowJob != nil {
				jobID = c.WorkflowJob.ID
				decodedCheckRunID, err := graphqlid.DecodeInt64ID(c.WorkflowJob.CheckRunID.String())
				s.Require().NoError(err)
				checkRunID = decodedCheckRunID
			}

			s.usageClient.EXPECT().
				EmitUsage(
					mock.Anything,
					mock.Anything,
					jobID,
					checkRunID,
					mock.Anything,
					mock.Anything,
					mock.Anything,
				).Return(nil)

			jsr := JobStatusRequest{
				WorkflowId:  testWorkflowID,
				DisplayName: testJobNameB,
				Number:      1,
				JobId:       testJobIDA,
				ExternalId:  testExternalID,
				Runtime:     "ubuntu",
				Progress: &JobStatusRequest_Complete{
					Complete: &JobComplete{
						Result:      Result_RESULT_CANCELED,
						StartedAt:   testStartedAtProto,
						CompletedAt: testCompletedAtProto,
						Log: &Log{
							Url:       testJobLogsURL,
							Lines:     1,
							CreatedAt: testCompletedAtProto,
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
								Result:      Result_RESULT_CANCELED,
								StartedAt:   testStartedAtProto,
								CompletedAt: testCompletedAtProto,
								Log: &Log{
									Url:       "http://some-step-log.log",
									Lines:     2,
									CreatedAt: testCompletedAtProto,
								},
							},
						},
					},
				},
			}

			s.statusClient.EXPECT().
				UpdateCheckRun(
					mock.Anything,
					&jsr,
					UpdateCheckRunParams{
						CheckSuiteState: &testCheckSuiteState,
						CheckRunID:      testCheckRunID,
					},
				).Return(nil).Once()

			_, err := s.svc.JobStatus(context.Background(), &jsr)
			s.Require().NoError(err)
		})
	}
}

func (s *statusServiceSuite) Test_DeletedRepo_RunStatus_Skips_UpdateCheckSuite_But_Updates_Workflow_Builds() {
	fakeWorkflowCreatedTime := time.Now().UTC()
	queuedAtProto := timestamppb.New(testQueuedAt)
	testStartedAtProto := timestamppb.New(queuedAtProto.AsTime())
	testCompletedAtProto := timestamppb.New(testStartedAtProto.AsTime().Add(time.Minute))
	artifactsCreatedAt := timestamppb.Now()
	artifactsExpiresAt := timestamppb.New(time.Now().Add(time.Hour * 24))

	fakeCreatedTimeForRestoredRepo := fakeWorkflowCreatedTime.Add(10 * time.Minute)
	s.azpResourcesRepo.EXPECT().
		TryGet(mock.Anything, testRepositoryID).
		Return(&azptypes.BackingResources{
			CreationResult: azptypes.CreationResult{TenantID: testRepositoryID.String()},
			CreatedAt:      &fakeCreatedTimeForRestoredRepo, /* treat this as restored repo */
		}, nil)

	addressableId := testWorkflowBuildExecutionDbID
	addressableWorkflowRunAttempt := testWorkflowRunAttempt

	s.wfbRepo.ExpectedCalls = nil
	s.wfbRepo.
		EXPECT().
		Complete(mock.Anything, mock.Anything, mock.Anything, testWorkflowBuildDbID, build.WorkflowStateSucceeded).
		Return(nil)
	s.wfbRepo.
		EXPECT().
		GetDataForStatusPostback(mock.Anything, testWorkflowID).
		Return(
			&deployer.DataForStatusPostback{
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
				QueuedAt:    &testQueuedAt,
				StartedAt:   &testQueuedAt,
				CompletedAt: nil,
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
				WorkflowBuildExecutionDatabaseID: &addressableId,
				Attempt:                          &addressableWorkflowRunAttempt,
			},
			true,
			nil,
		)

	// re-init with newly instantiated dependencies
	s.svc = New(logger.TestLogger(), statter.NullStatter(), s.azpResourcesRepo, s.wfbRepo, s.jobRepo, s.ghClientFactory, s.githubTwirpClient, nil, false, s.hydro, nil, "test", false)

	rsr := &RunStatusRequest{
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
				StartedAt:   testStartedAtProto,
				CompletedAt: testCompletedAtProto,
				Conclusion:  RunConclusion_SUCCEEDED,
			},
		},
	}

	_, err := s.svc.RunStatus(context.Background(), rsr)

	s.Require().NoError(err)
	s.Require().Len(s.hydro.workflowEvents, 1)
	s.Equal(&hydroV0.WorkflowExecution{
		WorkflowStartTime:          queuedAtProto,
		WorkflowEndTime:            rsr.GetComplete().GetCompletedAt(),
		ExternalProvider:           hydroV0.WorkflowExecution_AZP,
		ExternalProviderReference:  "",
		InvokingUserId:             testUserID,
		WorkflowRepositoryGlobalId: "MDEwOlJlcG9zaXRvcnkz",
		WorkflowRepositoryOwnerId:  testUserID,
		WorkflowRepositorySha:      testCommitSHA.String(),
		WorkflowFilePath:           testWorkflowFile,
		WorkflowBuildId:            uint64(testWorkflowBuildDbID),
		WorkflowRepositoryId:       3,
		CheckSuiteGlobalId:         "MDEwOkNoZWNrU3VpdGUx",
		CheckSuiteConclusion:       2,
		QueuedAt:                   queuedAtProto,
		StartedAt:                  timestamppb.New(queuedAtProto.AsTime()),
		CompletedAt:                rsr.GetComplete().GetCompletedAt(),
		WorkflowName:               []byte("A Workflow"),
		Attempt:                    testWorkflowRunAttempt,
	}, s.hydro.workflowEvents[0])
}
