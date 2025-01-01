package results

import (
	"context"
	"io"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/google/uuid"
	mock "github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/suite"
	"google.golang.org/protobuf/proto"

	checksv1 "github.com/github/actions-proto/gen/go/checks/v1"
	resultspb "github.com/github/actions-proto/gen/go/results/api/v1"
	"github.com/github/go-auth/hmac"

	"google.golang.org/protobuf/types/known/timestamppb"

	"github.com/github/launch/clients/aqueduct"
	"github.com/github/launch/observability"
	"github.com/github/launch/observability/ctxstash"
	"github.com/github/launch/pkg/results/entities/checks"
	"github.com/github/launch/pkg/results/entities/events"
	"github.com/github/launch/types"
	"github.com/github/launch/utils/testutils"
)

type ResultsClientTestSuite struct {
	suite.Suite

	config Config

	mockAqueductClient        *aqueduct.MockClient
	mockWorkflowUpdateService *MockWorkflowUpdateService

	fixtures struct {
		workflowRunBackendID types.WorkflowExecutionID
		checkSuite           struct {
			id       int64
			globalID types.GlobalID
		}
		repository struct {
			id       int64
			globalID types.GlobalID
		}
		checkSuiteState           *types.CheckSuiteState
		logRetentionDays          int64
		eventCreatedAt            time.Time
		eventName                 string
		customerLabel             string
		dynamicWorkflowIntegrator string
		ignoreFromRunStartDelay   bool
		rerunInfo                 *types.RerunInfo
	}
}

func TestResultsClientTestSuite(t *testing.T) {
	suite.Run(t, new(ResultsClientTestSuite))
}

// newClient returns a new results client with a given http client for twirp requests.
// if the http client is nil, a mock will be used instead
func (suite *ResultsClientTestSuite) newClient(twirpHTTPClient *http.Client) *client {
	client, err := NewClient(
		suite.config,
		aqueduct.NewFactory(nil),   // will be replaced by mock
		testutils.NewNoopBreaker(), // aqueduct breaker
		twirpHTTPClient,
		testutils.NewNoopBreaker(), // twirp breaker
		observability.NewNullObservability(),
	)

	suite.NoError(err)
	suite.NotNil(client)

	client.aqueductClient = suite.mockAqueductClient

	if twirpHTTPClient == nil {
		// http client is null, we'll mock
		client.workflowUpdateService = suite.mockWorkflowUpdateService
	}

	return client
}

func (suite *ResultsClientTestSuite) SetupTest() {
	suite.mockAqueductClient = aqueduct.NewMockClient(suite.T())
	suite.mockWorkflowUpdateService = NewMockWorkflowUpdateService(suite.T())

	suite.config = Config{
		AqueductURL:           "https://aqueduct.local",
		AqueductAPIKey:        "not-a-real-key",
		AqueductAPIKeyVersion: 0,
		CoreURL:               "https://results-core.local",
		CoreHMACSecret:        "hmac-and-cheese",
	}

	suite.fixtures.workflowRunBackendID = types.NewRandomWorkflowExecutionID()
	suite.fixtures.repository.id = 1234567
	suite.fixtures.repository.globalID = types.GlobalID(testutils.EncodeGlobalID("Repository", suite.fixtures.repository.id))
	suite.fixtures.checkSuite.id = 123456789
	suite.fixtures.checkSuite.globalID = types.GlobalID(testutils.EncodeGlobalID("CheckSuite", suite.fixtures.checkSuite.id))
	suite.fixtures.checkSuiteState = &types.CheckSuiteState{
		RepositoryID: suite.fixtures.repository.globalID,
		CheckSuiteIDPair: types.IDPair{
			DatabaseID: suite.fixtures.checkSuite.id,
			GlobalID:   suite.fixtures.checkSuite.globalID,
		},
	}
	suite.fixtures.logRetentionDays = 90
	suite.fixtures.eventName = "dynamic"
	suite.fixtures.eventCreatedAt = time.Now()
	suite.fixtures.customerLabel = "top100"
	suite.fixtures.ignoreFromRunStartDelay = false
	suite.fixtures.dynamicWorkflowIntegrator = "pages"
}

func (suite *ResultsClientTestSuite) SetupSubTest() {
	suite.SetupTest()
}

func (suite *ResultsClientTestSuite) TestGlobalIDToDatabaseID() {
	testcases := []struct {
		name      string
		globalID  types.GlobalID
		typeName  string
		expectID  int64
		expectErr bool
	}{
		{
			name:      "repo global ID success",
			globalID:  suite.fixtures.repository.globalID,
			typeName:  types.GlobalIDRepositoryType,
			expectID:  suite.fixtures.repository.id,
			expectErr: false,
		},
		{
			name:      "check suite global ID success",
			globalID:  suite.fixtures.checkSuite.globalID,
			typeName:  types.GlobalIDCheckSuiteType,
			expectID:  suite.fixtures.checkSuite.id,
			expectErr: false,
		},
		{
			name:      "mismatched type name",
			globalID:  suite.fixtures.repository.globalID,
			typeName:  types.GlobalIDCheckSuiteType,
			expectID:  0,
			expectErr: true,
		},
		{
			name:      "invalid global ID",
			globalID:  types.GlobalID("invalid"),
			typeName:  types.GlobalIDRepositoryType,
			expectID:  0,
			expectErr: true,
		},
	}

	for _, tc := range testcases {
		suite.Run(tc.name, func() {
			id, err := globalIDToDatabaseID(tc.globalID, tc.typeName)
			if tc.expectErr {
				suite.Error(err)
			} else {
				suite.NoError(err)
			}
			suite.Equal(tc.expectID, id)
		})
	}
}

func (suite *ResultsClientTestSuite) TestCreateWorkflowRun() {
	suite.mockWorkflowUpdateService.EXPECT().
		WorkflowRunCreate(mock.Anything, &resultspb.WorkflowRunCreateRequest{
			WorkflowRunBackendId:      suite.fixtures.workflowRunBackendID.String(),
			RepositoryId:              suite.fixtures.repository.id,
			CheckSuiteId:              suite.fixtures.checkSuite.id,
			LogRetentionDays:          suite.fixtures.logRetentionDays,
			EventCreatedAt:            timestamppb.New(suite.fixtures.eventCreatedAt),
			EventName:                 suite.fixtures.eventName,
			CustomerLabel:             suite.fixtures.customerLabel,
			DynamicWorkflowIntegrator: suite.fixtures.dynamicWorkflowIntegrator,
			IgnoreFromRunStartDelay:   suite.fixtures.ignoreFromRunStartDelay,
		}).Return(&resultspb.WorkflowRunCreateResponse{
		Ok: true,
	}, nil)

	client := suite.newClient(nil)
	sloMetadata := &RunStartDelaySLOMetadata{
		EventCreatedAt:            suite.fixtures.eventCreatedAt,
		EventName:                 suite.fixtures.eventName,
		CustomerLabel:             suite.fixtures.customerLabel,
		DynamicWorkflowIntegrator: suite.fixtures.dynamicWorkflowIntegrator,
		IgnoreFromRunStartDelay:   suite.fixtures.ignoreFromRunStartDelay,
	}
	err := client.CreateWorkflowRun(context.Background(), suite.fixtures.workflowRunBackendID, suite.fixtures.checkSuiteState, suite.fixtures.logRetentionDays, sloMetadata, "")
	suite.NoError(err)
}

func (suite *ResultsClientTestSuite) TestCreateWorkflowRun_NotDynamicWorkflow() {
	suite.mockWorkflowUpdateService.EXPECT().
		WorkflowRunCreate(mock.Anything, &resultspb.WorkflowRunCreateRequest{
			WorkflowRunBackendId:      suite.fixtures.workflowRunBackendID.String(),
			RepositoryId:              suite.fixtures.repository.id,
			CheckSuiteId:              suite.fixtures.checkSuite.id,
			LogRetentionDays:          suite.fixtures.logRetentionDays,
			EventCreatedAt:            timestamppb.New(suite.fixtures.eventCreatedAt),
			EventName:                 suite.fixtures.eventName,
			CustomerLabel:             "none",
			DynamicWorkflowIntegrator: "",
			IgnoreFromRunStartDelay:   suite.fixtures.ignoreFromRunStartDelay,
		}).Return(&resultspb.WorkflowRunCreateResponse{
		Ok: true,
	}, nil)

	client := suite.newClient(nil)
	sloMetadata := &RunStartDelaySLOMetadata{
		EventCreatedAt:            suite.fixtures.eventCreatedAt,
		EventName:                 suite.fixtures.eventName,
		CustomerLabel:             "none",
		DynamicWorkflowIntegrator: "",
		IgnoreFromRunStartDelay:   suite.fixtures.ignoreFromRunStartDelay,
	}
	err := client.CreateWorkflowRun(context.Background(), suite.fixtures.workflowRunBackendID, suite.fixtures.checkSuiteState, suite.fixtures.logRetentionDays, sloMetadata, "")
	suite.NoError(err)
}

func (suite *ResultsClientTestSuite) TestCreateWorkflowRun_IgnoreFromRunStartDelay() {
	suite.mockWorkflowUpdateService.EXPECT().
		WorkflowRunCreate(mock.Anything, &resultspb.WorkflowRunCreateRequest{
			WorkflowRunBackendId:      suite.fixtures.workflowRunBackendID.String(),
			RepositoryId:              suite.fixtures.repository.id,
			CheckSuiteId:              suite.fixtures.checkSuite.id,
			LogRetentionDays:          suite.fixtures.logRetentionDays,
			EventCreatedAt:            timestamppb.New(suite.fixtures.eventCreatedAt),
			EventName:                 suite.fixtures.eventName,
			CustomerLabel:             "none",
			DynamicWorkflowIntegrator: "",
			IgnoreFromRunStartDelay:   true,
		}).Return(&resultspb.WorkflowRunCreateResponse{
		Ok: true,
	}, nil)

	client := suite.newClient(nil)
	sloMetadata := &RunStartDelaySLOMetadata{
		EventCreatedAt:            suite.fixtures.eventCreatedAt,
		EventName:                 suite.fixtures.eventName,
		CustomerLabel:             "none",
		DynamicWorkflowIntegrator: "",
		IgnoreFromRunStartDelay:   true,
	}
	err := client.CreateWorkflowRun(context.Background(), suite.fixtures.workflowRunBackendID, suite.fixtures.checkSuiteState, suite.fixtures.logRetentionDays, sloMetadata, "")
	suite.NoError(err)
}

func (suite *ResultsClientTestSuite) TestCreateWorkflowRunNoCheckSuiteDatabaseID() {
	checkSuiteStateNoDatabaseID := &types.CheckSuiteState{
		RepositoryID: suite.fixtures.repository.globalID,
		CheckSuiteIDPair: types.IDPair{
			GlobalID: suite.fixtures.checkSuite.globalID,
		},
	}
	suite.mockWorkflowUpdateService.EXPECT().
		WorkflowRunCreate(mock.Anything, &resultspb.WorkflowRunCreateRequest{
			WorkflowRunBackendId:      suite.fixtures.workflowRunBackendID.String(),
			RepositoryId:              suite.fixtures.repository.id,
			CheckSuiteId:              suite.fixtures.checkSuite.id,
			LogRetentionDays:          suite.fixtures.logRetentionDays,
			EventCreatedAt:            timestamppb.New(suite.fixtures.eventCreatedAt),
			EventName:                 suite.fixtures.eventName,
			CustomerLabel:             suite.fixtures.customerLabel,
			DynamicWorkflowIntegrator: suite.fixtures.dynamicWorkflowIntegrator,
			IgnoreFromRunStartDelay:   suite.fixtures.ignoreFromRunStartDelay,
		}).Return(&resultspb.WorkflowRunCreateResponse{
		Ok: true,
	}, nil)

	client := suite.newClient(nil)
	sloMetadata := &RunStartDelaySLOMetadata{
		EventCreatedAt:            suite.fixtures.eventCreatedAt,
		EventName:                 suite.fixtures.eventName,
		CustomerLabel:             suite.fixtures.customerLabel,
		DynamicWorkflowIntegrator: suite.fixtures.dynamicWorkflowIntegrator,
		IgnoreFromRunStartDelay:   suite.fixtures.ignoreFromRunStartDelay,
	}
	err := client.CreateWorkflowRun(context.Background(), suite.fixtures.workflowRunBackendID, checkSuiteStateNoDatabaseID, suite.fixtures.logRetentionDays, sloMetadata, "")
	suite.NoError(err)
}

func (suite *ResultsClientTestSuite) TestCreateWorkflowRun_PartialRerun() {
	suite.fixtures.rerunInfo = &types.RerunInfo{
		PlanID: "previous_plan_id",
		JobIDs: []string{"previous_job_id"},
	}
	suite.mockWorkflowUpdateService.EXPECT().
		WorkflowRunCreate(mock.Anything, &resultspb.WorkflowRunCreateRequest{
			WorkflowRunBackendId:                suite.fixtures.workflowRunBackendID.String(),
			RepositoryId:                        suite.fixtures.repository.id,
			CheckSuiteId:                        suite.fixtures.checkSuite.id,
			LogRetentionDays:                    suite.fixtures.logRetentionDays,
			EventCreatedAt:                      timestamppb.New(suite.fixtures.eventCreatedAt),
			EventName:                           suite.fixtures.eventName,
			CustomerLabel:                       suite.fixtures.customerLabel,
			DynamicWorkflowIntegrator:           suite.fixtures.dynamicWorkflowIntegrator,
			IgnoreFromRunStartDelay:             suite.fixtures.ignoreFromRunStartDelay,
			PreviousAttemptWorkflowRunBackendId: suite.fixtures.rerunInfo.PlanID,
		}).Return(&resultspb.WorkflowRunCreateResponse{
		Ok: true,
	}, nil)

	client := suite.newClient(nil)
	sloMetadata := &RunStartDelaySLOMetadata{
		EventCreatedAt:            suite.fixtures.eventCreatedAt,
		EventName:                 suite.fixtures.eventName,
		CustomerLabel:             suite.fixtures.customerLabel,
		DynamicWorkflowIntegrator: suite.fixtures.dynamicWorkflowIntegrator,
		IgnoreFromRunStartDelay:   suite.fixtures.ignoreFromRunStartDelay,
	}
	err := client.CreateWorkflowRun(context.Background(), suite.fixtures.workflowRunBackendID, suite.fixtures.checkSuiteState, suite.fixtures.logRetentionDays, sloMetadata, suite.fixtures.rerunInfo.PlanID)
	suite.NoError(err)
}

func (suite *ResultsClientTestSuite) TestGetWorkflowRunState() {
	suite.mockWorkflowUpdateService.EXPECT().
		GetWorkflowRunState(mock.Anything, &resultspb.GetWorkflowRunStateRequest{
			WorkflowRunBackendId: suite.fixtures.workflowRunBackendID.String(),
		}).Return(&resultspb.GetWorkflowRunStateResponse{
		Status:      checksv1.Status_STATUS_COMPLETED,
		CompletedAt: timestamppb.New(time.Now()),
	}, nil)

	client := suite.newClient(nil)
	_, err := client.GetWorkflowRunState(context.TODO(), suite.fixtures.workflowRunBackendID)
	suite.NoError(err)
}

func (suite *ResultsClientTestSuite) TestWorkflowUpdateServiceTwirpRequest() {
	testServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		hmacHeaderValue := r.Header.Get("Request-HMAC")
		suite.Require().NotEmpty(hmacHeaderValue)

		requestHMAC, err := hmac.ParseRequestHMAC(hmacHeaderValue)
		suite.Require().NoError(err)

		err = requestHMAC.Validate(suite.config.CoreHMACSecret)
		suite.Require().NoError(err)

		body, err := io.ReadAll(r.Body)
		suite.Require().NoError(err)

		var result resultspb.WorkflowRunCreateRequest
		err = proto.Unmarshal(body, &result)
		suite.Require().NoError(err)

		suite.Equal(suite.fixtures.workflowRunBackendID.String(), result.WorkflowRunBackendId)
		suite.Equal(suite.fixtures.repository.id, result.RepositoryId)
		suite.Equal(suite.fixtures.checkSuite.id, result.CheckSuiteId)
		suite.Equal(suite.fixtures.logRetentionDays, result.LogRetentionDays)
		suite.Equal(timestamppb.New(suite.fixtures.eventCreatedAt), result.EventCreatedAt)
		suite.Equal(suite.fixtures.eventName, result.EventName)
		suite.Equal(suite.fixtures.customerLabel, result.CustomerLabel)
		suite.Equal(suite.fixtures.dynamicWorkflowIntegrator, result.DynamicWorkflowIntegrator)
		suite.Equal(suite.fixtures.ignoreFromRunStartDelay, result.IgnoreFromRunStartDelay)

		bites, err := proto.Marshal(&resultspb.WorkflowRunCreateResponse{
			Ok: true,
		})
		suite.NoError(err)

		_, err = w.Write(bites)
		suite.NoError(err)
	}))

	suite.config.CoreURL = testServer.URL

	client := suite.newClient(testServer.Client())
	sloMetadata := &RunStartDelaySLOMetadata{
		EventCreatedAt:            suite.fixtures.eventCreatedAt,
		EventName:                 suite.fixtures.eventName,
		CustomerLabel:             suite.fixtures.customerLabel,
		DynamicWorkflowIntegrator: suite.fixtures.dynamicWorkflowIntegrator,
		IgnoreFromRunStartDelay:   suite.fixtures.ignoreFromRunStartDelay,
	}
	err := client.CreateWorkflowRun(context.Background(), suite.fixtures.workflowRunBackendID, suite.fixtures.checkSuiteState, suite.fixtures.logRetentionDays, sloMetadata, "")
	suite.NoError(err)
}

func (suite *ResultsClientTestSuite) TestGetWorkflowOrchestrationContexts() {
	suite.mockWorkflowUpdateService.EXPECT().
		GetWorkflowOrchestrationContexts(mock.Anything, &resultspb.GetWorkflowOrchestrationContextsRequest{
			WorkflowRunBackendId: suite.fixtures.workflowRunBackendID.String(),
		}).Return(&resultspb.GetWorkflowOrchestrationContextsResponse{
		OrchestrationContexts: []string{
			"orchestration-context-1",
			"orchestration-context-2",
		},
	}, nil)

	client := suite.newClient(nil)
	_, err := client.GetWorkflowOrchestrationContexts(context.TODO(), suite.fixtures.workflowRunBackendID)
	suite.NoError(err)
}

func (suite *ResultsClientTestSuite) TestUpdateWorkflowRun() {
	update := &events.WorkflowRunUpdate{
		RepositoryId:    suite.fixtures.repository.id,
		CheckSuiteId:    suite.fixtures.checkSuite.id,
		WorkflowRunGuid: suite.fixtures.workflowRunBackendID.String(),
		Status:          checks.CheckStatus_STATUS_COMPLETED,
		Conclusion:      checks.CheckConclusion_CONCLUSION_STARTUP_FAILURE,
		CompletedAt:     timestamppb.Now(),
	}

	payload, err := proto.Marshal(update)
	suite.NoError(err)

	suite.mockAqueductClient.EXPECT().Send(mock.Anything, aqueduct.Job{
		App:     resultsAqueductApp,
		Queue:   actionsResultsEventsQueue,
		Payload: payload,
		Headers: map[string]string{
			actionsResultsEventHeader:    workflowRunUpdateEvent,
			RequestIDHeader:              "",
			ctxstash.VSSCorrelationIDKey: "",
		},
	}, mock.Anything, mock.Anything).
		Return(uuid.NewString(), nil)

	client := suite.newClient(nil)
	err = client.UpdateWorkflowRun(context.Background(), update)
	suite.NoError(err)
}
