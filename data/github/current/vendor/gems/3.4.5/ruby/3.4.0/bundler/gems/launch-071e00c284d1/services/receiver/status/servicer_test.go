package status_test

import (
	"bytes"
	"context"
	"encoding/base64"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/facebookgo/clock"
	"github.com/go-chi/chi"
	"github.com/golang/protobuf/ptypes/empty"
	tspb "github.com/golang/protobuf/ptypes/timestamp"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"
	"github.com/stretchr/testify/suite"
	"google.golang.org/protobuf/types/known/timestamppb"

	"github.com/github/launch/clients/ghtwirp"
	"github.com/github/launch/clients/github"
	"github.com/github/launch/observability/azpcorrelation"
	"github.com/github/launch/observability/ctxstash"
	"github.com/github/launch/observability/logger"
	"github.com/github/launch/observability/measurehttp"
	"github.com/github/launch/observability/statter"
	"github.com/github/launch/services/auth/hkdf"
	deployer "github.com/github/launch/services/deploy/status"
	svcerr "github.com/github/launch/services/errors"
	"github.com/github/launch/services/receiver/status"
)

const (
	validWorkflowID = "c6138ef3-98fe-4a76-bd86-7c6045a3c141"
	validJobID      = "fa5aabba-8868-4de2-aa56-0f0320489fe9"
	timestamp       = "2019-07-03T14:33:44Z"
	startedTime     = "2019-01-01T00:00:00Z"
	completedTime   = "2019-01-01T00:01:00Z"
	expiresTime     = "2019-08-03T14:33:44Z"
)

var rawSignature = []byte("NewPhoneWhoDis")

func middlewareForHeader(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		ctx := r.Context()
		vssID := r.Header.Get(azpcorrelation.VSSE2EIDHeaderName)
		ctx = ctxstash.WithVSSRequestID(ctx, vssID)
		ctx = azpcorrelation.WithVSSID(ctx, vssID)
		w.Header().Set(azpcorrelation.VSSE2EIDHeaderName, vssID)
		next.ServeHTTP(w, r.WithContext(ctx))
	})
}

func fixture(t *testing.T, name string) []byte {
	data, err := os.ReadFile(filepath.Join("fixtures", name))
	require.NoError(t, err, "Reading %s fixture should not error", name)
	return data
}

type ServiceSuite struct {
	suite.Suite
	servicer      *status.Servicer
	deployer      *deployer.MockLaunchStatusService
	verifier      *hkdf.MockVerifier
	clock         clock.Clock
	ghTwirpClient *ghtwirp.MockClient
}

func TestStatusServiceSuite(t *testing.T) {
	suite.Run(t, new(ServiceSuite))
}

func (s *ServiceSuite) TearDownTest() {
	s.deployer.AssertExpectations(s.T())
	s.verifier.AssertExpectations(s.T())
	s.ghTwirpClient.AssertExpectations(s.T())
}

func (s *ServiceSuite) SetupTest() {
	s.deployer = &deployer.MockLaunchStatusService{}
	s.verifier = &hkdf.MockVerifier{}

	s.ghTwirpClient = &ghtwirp.MockClient{}

	s.clock = clock.New()
	s.servicer = &status.Servicer{
		Log:           logger.NullLogger(),
		Stats:         statter.NullStatter(),
		Verifier:      s.verifier,
		Deployer:      s.deployer,
		ReceiverURL:   "https://launch-receiver-test.githubapp.com",
		GHTwirpClient: s.ghTwirpClient,
		IsLab:         false,
	}
}

func (s *ServiceSuite) TestStatusMissingSignature() {
	res := httptest.NewRecorder()
	req := s.getJobHTTPStatusRequest(http.MethodPatch, validWorkflowID, validJobID, nil)
	req.Header.Del("Authorization")
	s.servicer.HandleJobStatus(res, req)
	s.Equal(http.StatusBadRequest, res.Code)
}

func (s *ServiceSuite) TestResourceExhausted() {
	res := httptest.NewRecorder()
	req := s.getJobHTTPStatusRequest(http.MethodPatch, validWorkflowID, validJobID, nil)
	s.ghTwirpClient.On("IsFeatureEnabledGlobally", mock.Anything, github.DisableStatusPostbacksFeatureFlag).Return(false)
	s.deployer.On("JobStatus", mock.Anything, mock.Anything).Return(&empty.Empty{}, svcerr.NewResourceExhaustedError("exhausted"))
	s.verifier.On("Verify", mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(true, nil)
	s.servicer.HandleJobStatus(res, req)
	s.Equal(http.StatusTooManyRequests, res.Code)
}

func (s *ServiceSuite) TestRunStatusWithStatusPostbacksDisabledInProduction() {
	body := bytes.NewReader(fixture(s.T(), "run_status_postback.json"))
	res := httptest.NewRecorder()
	req := s.getRunHTTPStatusRequest(http.MethodPatch, validWorkflowID, body)

	s.deployer = &deployer.MockLaunchStatusService{}
	s.servicer.IsLab = false
	s.ghTwirpClient.ExpectedCalls = []*mock.Call{}
	s.ghTwirpClient.On("IsFeatureEnabledGlobally", mock.Anything, github.DisableStatusPostbacksFeatureFlag).Return(true)
	s.verifier.On("Verify", mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(true, nil)
	s.servicer.HandleRunStatus(res, req)
	s.Equal(http.StatusTooManyRequests, res.Code)
}

func (s *ServiceSuite) TestJobStatusWithStatusPostbacksDisabledInProduction() {
	reqBody := bytes.NewReader(fixture(s.T(), "job_status_update_postback_completed.json"))
	res := httptest.NewRecorder()
	req := s.getJobHTTPStatusRequest(http.MethodPatch, validWorkflowID, validJobID, reqBody)

	s.deployer = &deployer.MockLaunchStatusService{}
	s.servicer.IsLab = false
	s.ghTwirpClient.ExpectedCalls = []*mock.Call{}
	s.ghTwirpClient.On("IsFeatureEnabledGlobally", mock.Anything, github.DisableStatusPostbacksFeatureFlag).Return(true)
	s.verifier.On("Verify", mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(true, nil)
	s.servicer.HandleJobStatus(res, req)

	s.Equal(http.StatusTooManyRequests, res.Code)
}

func (s *ServiceSuite) TestJobStatusWithCompletedWithEnvironmentNameAndUrl() {
	startedAt := s.getProtoTime("2019-06-03T12:34:56Z")
	completedAt := s.getProtoTime("2019-06-03T12:35:56Z")
	expiresAt := s.getProtoTime("2019-07-03T12:35:56Z")

	reqBody := bytes.NewReader(fixture(s.T(), "job_status_update_postback_completed_with_environment_name_url.json"))
	res := httptest.NewRecorder()
	req := s.getJobHTTPStatusRequest(http.MethodPatch, validWorkflowID, validJobID, reqBody)

	s.deployer = &deployer.MockLaunchStatusService{}
	s.deployer.On("JobStatus", mock.Anything, &deployer.JobStatusRequest{
		WorkflowId:  validWorkflowID,
		JobId:       validJobID,
		DisplayName: "Run tests",
		ExternalId:  "abc-123",
		Number:      5,
		Progress: &deployer.JobStatusRequest_Complete{
			Complete: &deployer.JobComplete{
				Result:      deployer.Result_RESULT_SUCCEEDED,
				StartedAt:   startedAt,
				CompletedAt: completedAt,
				Log: &deployer.Log{
					Url:       "https://actions.githubusercontent.com/completed-logs/1",
					Lines:     101,
					CreatedAt: completedAt,
				},
			},
		},
		Artifacts: []*deployer.Artifact{{
			Name:      "foo.png",
			Size:      1024,
			Url:       "https://actions.githubusercontent.com/artifacts/screenshots/foo.png",
			CreatedAt: completedAt,
			ExpiresAt: expiresAt,
		}},
		Steps: []*deployer.JobStep{{
			Name:       "npm test",
			ExternalId: "def-456",
			Number:     0,
			Progress: &deployer.JobStep_Complete{
				Complete: &deployer.StepComplete{
					Result:      deployer.Result_RESULT_SUCCEEDED,
					StartedAt:   startedAt,
					CompletedAt: completedAt,
					Log: &deployer.Log{
						Url:       "https://actions.githubusercontent.com/logs/1",
						Lines:     102,
						CreatedAt: completedAt,
					},
				},
			},
		}},
		Environment: &deployer.Environment{
			Name: "staging",
			Url:  "https://github.com",
		},
	}).Return(&empty.Empty{}, nil)
	s.servicer.Deployer = s.deployer
	s.ghTwirpClient.On("IsFeatureEnabledGlobally", mock.Anything, github.DisableStatusPostbacksFeatureFlag).Return(false)
	s.verifier.On("Verify", mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(true, nil)
	s.servicer.HandleJobStatus(res, req)
	s.Equal(http.StatusOK, res.Code)
	s.Empty(res.Body)
}

func (s *ServiceSuite) TestJobStatusWithConcurrency() {

	reqBody := bytes.NewReader(fixture(s.T(), "job_status_update_postback_with_concurrency.json"))
	res := httptest.NewRecorder()
	req := s.getJobHTTPStatusRequest(http.MethodPatch, validWorkflowID, validJobID, reqBody)

	s.deployer = &deployer.MockLaunchStatusService{}
	s.deployer.On("JobStatus", mock.Anything, &deployer.JobStatusRequest{
		WorkflowId:  validWorkflowID,
		JobId:       validJobID,
		DisplayName: "Run tests",
		ExternalId:  "abc-123",
		Number:      5,
		Steps: []*deployer.JobStep{{
			Name:       "npm test",
			ExternalId: "def-456",
			Number:     0,
			Progress: &deployer.JobStep_Queued{
				Queued: &deployer.StepQueued{},
			},
		}},
		Progress: &deployer.JobStatusRequest_InProgress{
			InProgress: &deployer.JobInProgress{
				Status: deployer.Status_STATUS_PENDING,
			},
		},
		Environment: &deployer.Environment{
			Name: "staging",
			Url:  "https://github.com",
		},
		Concurrency: &deployer.Concurrency{
			Group: "testGroup",
		},
	}).Return(&empty.Empty{}, nil)
	s.servicer.Deployer = s.deployer
	s.ghTwirpClient.On("IsFeatureEnabledGlobally", mock.Anything, github.DisableStatusPostbacksFeatureFlag).Return(false)
	s.verifier.On("Verify", mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(true, nil)
	s.servicer.HandleJobStatus(res, req)
	s.Equal(http.StatusOK, res.Code)
	s.Empty(res.Body)
}

func (s *ServiceSuite) TestJobStatusWithConcurrencyWaitingOnResource() {

	reqBody := bytes.NewReader(fixture(s.T(), "job_status_update_postback_with_concurrency_waiting_on_resource.json"))
	res := httptest.NewRecorder()
	req := s.getJobHTTPStatusRequest(http.MethodPatch, validWorkflowID, validJobID, reqBody)

	s.deployer = &deployer.MockLaunchStatusService{}
	s.deployer.On("JobStatus", mock.Anything, &deployer.JobStatusRequest{
		WorkflowId:  validWorkflowID,
		JobId:       validJobID,
		DisplayName: "Run tests",
		ExternalId:  "abc-123",
		Number:      5,
		Steps: []*deployer.JobStep{{
			Name:       "npm test",
			ExternalId: "def-456",
			Number:     0,
			Progress: &deployer.JobStep_Queued{
				Queued: &deployer.StepQueued{},
			},
		}},
		Environment: &deployer.Environment{
			Name: "staging",
			Url:  "https://github.com",
		},
		Progress: &deployer.JobStatusRequest_InProgress{
			InProgress: &deployer.JobInProgress{
				Status: deployer.Status_STATUS_PENDING,
			},
		},
		Concurrency: &deployer.Concurrency{
			Group: "testGroup",
			WaitingOnResource: &deployer.WaitingOnResource{
				JobExternalId: "id456",
				Identifier:    "test",
			},
		},
	}).Return(&empty.Empty{}, nil)
	s.servicer.Deployer = s.deployer
	s.ghTwirpClient.On("IsFeatureEnabledGlobally", mock.Anything, github.DisableStatusPostbacksFeatureFlag).Return(false)
	s.verifier.On("Verify", mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(true, nil)
	s.servicer.HandleJobStatus(res, req)
	s.Equal(http.StatusOK, res.Code)
	s.Empty(res.Body)
}

func (s *ServiceSuite) TestJobStatusWithLabels() {
	reqBody := bytes.NewReader(fixture(s.T(), "job_status_update_postback_with_labels.json"))
	res := httptest.NewRecorder()
	req := s.getJobHTTPStatusRequest(http.MethodPatch, validWorkflowID, validJobID, reqBody)

	s.deployer = &deployer.MockLaunchStatusService{}
	s.deployer.On("JobStatus", mock.Anything, &deployer.JobStatusRequest{
		WorkflowId:  validWorkflowID,
		JobId:       validJobID,
		DisplayName: "Run tests",
		ExternalId:  "abc-123",
		Number:      5,
		Progress: &deployer.JobStatusRequest_InProgress{
			InProgress: &deployer.JobInProgress{
				Status: deployer.Status_STATUS_PENDING,
			},
		},
		Concurrency: &deployer.Concurrency{
			Group: "testGroup",
			WaitingOnResource: &deployer.WaitingOnResource{
				JobExternalId: "id456",
			},
		},
		Labels: []string{"foo", "bar"},
	}).Return(&empty.Empty{}, nil)
	s.servicer.Deployer = s.deployer
	s.ghTwirpClient.On("IsFeatureEnabledGlobally", mock.Anything, github.DisableStatusPostbacksFeatureFlag).Return(false)
	s.verifier.On("Verify", mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(true, nil)
	s.servicer.HandleJobStatus(res, req)
	s.Equal(http.StatusOK, res.Code)
	s.Empty(res.Body)
}

func (s *ServiceSuite) TestStatusInvalidSignatureEncoding() {
	res := httptest.NewRecorder()
	req := s.getJobHTTPStatusRequest(http.MethodPatch, validWorkflowID, validJobID, nil)
	req.Header.Set("Authorization", "😱")
	s.servicer.HandleJobStatus(res, req)
	s.Equal(http.StatusBadRequest, res.Code)
}

func (s *ServiceSuite) TestStatusWithInvalidStatusUpdateMessage() {
	res := httptest.NewRecorder()
	req := s.getJobHTTPStatusRequest(http.MethodPatch, validWorkflowID, validJobID, bytes.NewReader([]byte("{}")))
	s.verifier.On("Verify", mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(true, nil)
	s.ghTwirpClient.On("IsFeatureEnabledGlobally", mock.Anything, github.DisableStatusPostbacksFeatureFlag).Return(false)
	s.servicer.HandleJobStatus(res, req)
	s.Equal(http.StatusBadRequest, res.Code)
}

func (s *ServiceSuite) TestJobStatusCorrelationHeaders() {
	res := httptest.NewRecorder()
	req := s.getJobHTTPStatusRequest(http.MethodPatch, validWorkflowID, validJobID, bytes.NewReader([]byte("{}")))
	req.Header.Set(azpcorrelation.VSSE2EIDHeaderName, "test-value")
	req.Header.Set("Authorization", "TmV3UGhvbmVXaG9EaXM=")
	handlerForHandleRunStatus := middlewareForHeader(http.HandlerFunc(s.servicer.HandleRunStatus))
	handlerForHandleRunStatus.ServeHTTP(res, req)
	s.Assert().Equal(http.StatusBadRequest, res.Code)
	s.Assert().Equal(res.Header().Get(azpcorrelation.VSSE2EIDHeaderName), "test-value")
}

func (s *ServiceSuite) TestStatusWithInProgressStatusUpdateMessage() {
	startedAt := s.getProtoTime("2019-06-03T12:34:56Z")
	expiresAt := s.getProtoTime("2019-06-03T12:36:56Z")

	reqBody := bytes.NewReader(fixture(s.T(), "job_status_update_postback_in_progress.json"))
	res := httptest.NewRecorder()
	req := s.getJobHTTPStatusRequest(http.MethodPatch, validWorkflowID, validJobID, reqBody)
	s.deployer.On("JobStatus", mock.Anything, &deployer.JobStatusRequest{
		WorkflowId:  validWorkflowID,
		JobId:       validJobID,
		DisplayName: "Run tests",
		ExternalId:  "abc-123",
		Number:      5,
		Progress: &deployer.JobStatusRequest_InProgress{
			InProgress: &deployer.JobInProgress{
				Status:    deployer.Status_STATUS_IN_PROGRESS,
				StartedAt: startedAt,
				LogStream: &deployer.LogStream{
					Url:       "https://actions.githubusercontent.com/streaming-logs/1",
					Token:     "ohdu2eez4Ho8uquohz7ugh2gieLeizei",
					ExpiresAt: expiresAt,
				},
			},
		},
		Artifacts: nil,
		Steps: []*deployer.JobStep{{
			Name:       "npm test",
			ExternalId: "def-456",
			Number:     0,
			Progress: &deployer.JobStep_InProgress{
				InProgress: &deployer.StepInProgress{
					Status:    deployer.Status_STATUS_IN_PROGRESS,
					StartedAt: startedAt,
				},
			},
		}, {
			Name:       "npm publish",
			ExternalId: "def-789",
			Number:     1,
			Progress: &deployer.JobStep_Queued{
				Queued: &deployer.StepQueued{},
			},
		}},
	}).Return(&empty.Empty{}, nil)
	s.ghTwirpClient.On("IsFeatureEnabledGlobally", mock.Anything, github.DisableStatusPostbacksFeatureFlag).Return(false)
	s.verifier.On("Verify", mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(true, nil)
	s.servicer.HandleJobStatus(res, req)
	s.Equal(http.StatusOK, res.Code)
}

func (s *ServiceSuite) TestStatusWithInProgressWithEnvironmentName() {
	startedAt := s.getProtoTime("2019-06-03T12:34:56Z")
	expiresAt := s.getProtoTime("2019-06-03T12:36:56Z")

	reqBody := bytes.NewReader(fixture(s.T(), "job_status_update_postback_in_progress_with_environment_name.json"))
	res := httptest.NewRecorder()
	req := s.getJobHTTPStatusRequest(http.MethodPatch, validWorkflowID, validJobID, reqBody)
	s.deployer.On("JobStatus", mock.Anything, &deployer.JobStatusRequest{
		WorkflowId:  validWorkflowID,
		JobId:       validJobID,
		DisplayName: "Run tests",
		ExternalId:  "abc-123",
		Number:      5,
		Progress: &deployer.JobStatusRequest_InProgress{
			InProgress: &deployer.JobInProgress{
				Status:    deployer.Status_STATUS_IN_PROGRESS,
				StartedAt: startedAt,
				LogStream: &deployer.LogStream{
					Url:       "https://actions.githubusercontent.com/streaming-logs/1",
					Token:     "ohdu2eez4Ho8uquohz7ugh2gieLeizei",
					ExpiresAt: expiresAt,
				},
			},
		},
		Artifacts: nil,
		Steps: []*deployer.JobStep{{
			Name:       "npm test",
			ExternalId: "def-456",
			Number:     0,
			Progress: &deployer.JobStep_InProgress{
				InProgress: &deployer.StepInProgress{
					Status:    deployer.Status_STATUS_IN_PROGRESS,
					StartedAt: startedAt,
				},
			},
		}, {
			Name:       "npm publish",
			ExternalId: "def-789",
			Number:     1,
			Progress: &deployer.JobStep_Queued{
				Queued: &deployer.StepQueued{},
			},
		}},
		Environment: &deployer.Environment{
			Name: "staging",
		},
	}).Return(&empty.Empty{}, nil)
	s.ghTwirpClient.On("IsFeatureEnabledGlobally", mock.Anything, github.DisableStatusPostbacksFeatureFlag).Return(false)
	s.verifier.On("Verify", mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(true, nil)
	s.servicer.HandleJobStatus(res, req)
	s.Equal(http.StatusOK, res.Code)
}

func (s *ServiceSuite) TestStatusWithInProgressStatusAndNoLogStreamUpdateMessage() {
	startedAt := s.getProtoTime("2019-06-03T12:34:56Z")

	reqBody := bytes.NewReader(fixture(s.T(), "job_status_update_postback_in_progress_no_log_stream.json"))
	res := httptest.NewRecorder()
	req := s.getJobHTTPStatusRequest(http.MethodPatch, validWorkflowID, validJobID, reqBody)
	s.deployer.On("JobStatus", mock.Anything, &deployer.JobStatusRequest{
		WorkflowId:  validWorkflowID,
		JobId:       validJobID,
		DisplayName: "Run tests",
		ExternalId:  "abc-123",
		Number:      5,
		Progress: &deployer.JobStatusRequest_InProgress{
			InProgress: &deployer.JobInProgress{
				Status:    deployer.Status_STATUS_IN_PROGRESS,
				StartedAt: startedAt,
			},
		},
		Artifacts: nil,
		Steps: []*deployer.JobStep{{
			Name:       "npm test",
			ExternalId: "def-456",
			Number:     0,
			Progress: &deployer.JobStep_InProgress{
				InProgress: &deployer.StepInProgress{
					Status:    deployer.Status_STATUS_IN_PROGRESS,
					StartedAt: startedAt,
				},
			},
		}},
	}).Return(&empty.Empty{}, nil)
	s.ghTwirpClient.On("IsFeatureEnabledGlobally", mock.Anything, github.DisableStatusPostbacksFeatureFlag).Return(false)
	s.verifier.On("Verify", mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(true, nil)
	s.servicer.HandleJobStatus(res, req)
	s.Equal(http.StatusOK, res.Code)
}

func (s *ServiceSuite) TestStatusWithCompletedStatusUpdateMessage() {
	startedAt := s.getProtoTime("2019-06-03T12:34:56Z")
	completedAt := s.getProtoTime("2019-06-03T12:35:56Z")
	expiresAt := s.getProtoTime("2019-07-03T12:35:56Z")

	reqBody := bytes.NewReader(fixture(s.T(), "job_status_update_postback_completed.json"))
	res := httptest.NewRecorder()
	req := s.getJobHTTPStatusRequest(http.MethodPatch, validWorkflowID, validJobID, reqBody)
	s.deployer.On("JobStatus", mock.Anything, &deployer.JobStatusRequest{
		WorkflowId:  validWorkflowID,
		JobId:       validJobID,
		DisplayName: "Run tests",
		ExternalId:  "abc-123",
		Number:      5,
		Progress: &deployer.JobStatusRequest_Complete{
			Complete: &deployer.JobComplete{
				Result:      deployer.Result_RESULT_SUCCEEDED,
				StartedAt:   startedAt,
				CompletedAt: completedAt,
				Log: &deployer.Log{
					Url:       "https://actions.githubusercontent.com/completed-logs/1",
					Lines:     101,
					CreatedAt: completedAt,
				},
			},
		},
		Artifacts: []*deployer.Artifact{{
			Name:      "foo.png",
			Size:      1024,
			Url:       "https://actions.githubusercontent.com/artifacts/screenshots/foo.png",
			CreatedAt: completedAt,
			ExpiresAt: expiresAt,
		}},
		Steps: []*deployer.JobStep{{
			Name:       "npm test",
			ExternalId: "def-456",
			Number:     0,
			Progress: &deployer.JobStep_Complete{
				Complete: &deployer.StepComplete{
					Result:      deployer.Result_RESULT_SUCCEEDED,
					StartedAt:   startedAt,
					CompletedAt: completedAt,
					Log: &deployer.Log{
						Url:       "https://actions.githubusercontent.com/logs/1",
						Lines:     102,
						CreatedAt: completedAt,
					},
				},
			},
		}},
	}).Return(&empty.Empty{}, nil)
	s.ghTwirpClient.On("IsFeatureEnabledGlobally", mock.Anything, github.DisableStatusPostbacksFeatureFlag).Return(false)
	s.verifier.On("Verify", mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(true, nil)
	s.servicer.HandleJobStatus(res, req)
	s.Equal(http.StatusOK, res.Code)
}

func (s *ServiceSuite) TestStatusWithCompletedStatusUpdateMessageWithAnnotations() {
	startedAt := s.getProtoTime("2019-06-03T12:34:56Z")
	completedAt := s.getProtoTime("2019-06-03T12:35:56Z")
	expiresAt := s.getProtoTime("2019-07-03T12:35:56Z")

	reqBody := bytes.NewReader(fixture(s.T(), "job_status_update_postback_completed_with_annotations.json"))
	res := httptest.NewRecorder()
	req := s.getJobHTTPStatusRequest(http.MethodPatch, validWorkflowID, validJobID, reqBody)
	s.deployer.On("JobStatus", mock.Anything, &deployer.JobStatusRequest{
		WorkflowId:  validWorkflowID,
		JobId:       validJobID,
		DisplayName: "Run tests",
		ExternalId:  "abc-123",
		Number:      5,
		Progress: &deployer.JobStatusRequest_Complete{
			Complete: &deployer.JobComplete{
				Result:      deployer.Result_RESULT_SUCCEEDED,
				StartedAt:   startedAt,
				CompletedAt: completedAt,
				Log: &deployer.Log{
					Url:       "https://actions.githubusercontent.com/completed-logs/1",
					Lines:     101,
					CreatedAt: completedAt,
				},
			},
		},
		Annotations: []*deployer.Annotation{
			{
				AnnotationLevel: deployer.AnnotationLevel_LEVEL_WARNING,
				Message:         "annotation message",
				RawDetails:      "annotation raw details",
				Path:            ".github/workflows/ci.yaml",
				StartLine:       1,
				EndLine:         1,
				StartColumn:     1,
				EndColumn:       5,
			},
			{
				AnnotationLevel: deployer.AnnotationLevel_LEVEL_NOTICE,
				Message:         "annotation message",
				RawDetails:      "annotation raw details",
				Path:            ".github/workflows/cd.yaml",
				StartLine:       1,
				EndLine:         2,
			},
			{
				AnnotationLevel: deployer.AnnotationLevel_LEVEL_FAILURE,
				Message:         "missing path",
				RawDetails:      "annotation raw details",
				Path:            status.DefaultAnnotationPath,
				StartLine:       1,
				EndLine:         2,
			},
			{
				AnnotationLevel: deployer.AnnotationLevel_LEVEL_FAILURE,
				Message:         "missing lines",
				RawDetails:      "annotation raw details",
				Path:            ".github/workflows/cd.yaml",
				StartLine:       1,
				EndLine:         1,
			},
			{
				AnnotationLevel: deployer.AnnotationLevel_LEVEL_FAILURE,
				Message:         "zero lines",
				RawDetails:      "annotation raw details",
				Path:            ".github/workflows/cd.yaml",
				StartLine:       1,
				EndLine:         1,
			},
			{
				AnnotationLevel: deployer.AnnotationLevel_LEVEL_FAILURE,
				Message:         "multi-lines with columns",
				RawDetails:      "annotation raw details",
				Path:            ".github/workflows/cd.yaml",
				StartLine:       1,
				EndLine:         2,
				StartColumn:     0,
				EndColumn:       0,
			},
			{
				AnnotationLevel: deployer.AnnotationLevel_LEVEL_FAILURE,
				Message:         "bad start/end columns",
				RawDetails:      "annotation raw details",
				Path:            ".github/workflows/cd.yaml",
				StartLine:       1,
				EndLine:         1,
				StartColumn:     5,
				EndColumn:       5,
			},
		},
		Artifacts: []*deployer.Artifact{{
			Name:      "foo.png",
			Size:      1024,
			Url:       "https://actions.githubusercontent.com/artifacts/screenshots/foo.png",
			CreatedAt: completedAt,
			ExpiresAt: expiresAt,
		}},
		Steps: []*deployer.JobStep{{
			Name:       "npm test",
			ExternalId: "def-456",
			Number:     0,
			Progress: &deployer.JobStep_Complete{
				Complete: &deployer.StepComplete{
					Result:      deployer.Result_RESULT_SUCCEEDED,
					StartedAt:   startedAt,
					CompletedAt: completedAt,
					Log: &deployer.Log{
						Url:       "https://actions.githubusercontent.com/logs/1",
						Lines:     102,
						CreatedAt: completedAt,
					},
				},
			},
		}},
	}).Return(&empty.Empty{}, nil)
	s.ghTwirpClient.On("IsFeatureEnabledGlobally", mock.Anything, github.DisableStatusPostbacksFeatureFlag).Return(false)
	s.verifier.On("Verify", mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(true, nil)
	s.servicer.HandleJobStatus(res, req)
	s.Equal(http.StatusOK, res.Code)
}

func (s *ServiceSuite) TestStatusWithCompletedStatusNoLogsUpdateMessage() {
	startedAt := s.getProtoTime("2019-06-03T12:34:56Z")
	completedAt := s.getProtoTime("2019-06-03T12:35:56Z")
	expiresAt := s.getProtoTime("2019-07-03T12:35:56Z")

	reqBody := bytes.NewReader(fixture(s.T(), "job_status_update_postback_completed_no_logs.json"))
	res := httptest.NewRecorder()
	req := s.getJobHTTPStatusRequest(http.MethodPatch, validWorkflowID, validJobID, reqBody)
	req.Header.Set("Authorization", s.getAuthorizationHeader())
	s.deployer.On("JobStatus", mock.Anything, &deployer.JobStatusRequest{
		WorkflowId:  validWorkflowID,
		JobId:       validJobID,
		DisplayName: "Run tests",
		ExternalId:  "abc-123",
		Number:      5,
		Progress: &deployer.JobStatusRequest_Complete{
			Complete: &deployer.JobComplete{
				Result:      deployer.Result_RESULT_SUCCEEDED,
				StartedAt:   startedAt,
				CompletedAt: completedAt,
				Log:         nil,
			},
		},
		Artifacts: []*deployer.Artifact{{
			Name:      "foo.png",
			Size:      1024,
			Url:       "https://actions.githubusercontent.com/artifacts/screenshots/foo.png",
			CreatedAt: completedAt,
			ExpiresAt: expiresAt,
		}},
		Steps: []*deployer.JobStep{{
			Name:       "npm test",
			ExternalId: "def-456",
			Number:     0,
			Progress: &deployer.JobStep_Complete{
				Complete: &deployer.StepComplete{
					Result:      deployer.Result_RESULT_SUCCEEDED,
					StartedAt:   startedAt,
					CompletedAt: completedAt,
					Log:         nil,
				},
			},
		}},
	}).Return(&empty.Empty{}, nil)
	s.ghTwirpClient.On("IsFeatureEnabledGlobally", mock.Anything, github.DisableStatusPostbacksFeatureFlag).Return(false)
	s.verifier.On("Verify", mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(true, nil)
	s.servicer.HandleJobStatus(res, req)
	s.Equal(http.StatusOK, res.Code)
}

func (s *ServiceSuite) TestStatusWithCompletedStatusUpdateMessageWithSummaryUrl() {
	startedAt := s.getProtoTime("2019-06-03T12:34:56Z")
	completedAt := s.getProtoTime("2019-06-03T12:35:56Z")
	expiresAt := s.getProtoTime("2019-07-03T12:35:56Z")

	reqBody := bytes.NewReader(fixture(s.T(), "job_status_update_postback_completed_with_summary_url.json"))
	res := httptest.NewRecorder()
	req := s.getJobHTTPStatusRequest(http.MethodPatch, validWorkflowID, validJobID, reqBody)
	s.deployer.On("JobStatus", mock.Anything, &deployer.JobStatusRequest{
		WorkflowId:  validWorkflowID,
		JobId:       validJobID,
		DisplayName: "Run tests",
		ExternalId:  "abc-123",
		Number:      5,
		Progress: &deployer.JobStatusRequest_Complete{
			Complete: &deployer.JobComplete{
				Result:      deployer.Result_RESULT_SUCCEEDED,
				StartedAt:   startedAt,
				CompletedAt: completedAt,
				SummaryUrl:  "https://codedev.ms/test/_apis/pipelines/plans/e3ef0826-5a8d-4b55-953b-b0e78abb4d17/summary?job=c92e7b95-6554-40c3-aff3-4e0ef3f36ffe",
				Log: &deployer.Log{
					Url:       "https://actions.githubusercontent.com/completed-logs/1",
					Lines:     101,
					CreatedAt: completedAt,
				},
			},
		},
		Artifacts: []*deployer.Artifact{{
			Name:      "foo.png",
			Size:      1024,
			Url:       "https://actions.githubusercontent.com/artifacts/screenshots/foo.png",
			CreatedAt: completedAt,
			ExpiresAt: expiresAt,
		}},
		Steps: []*deployer.JobStep{{
			Name:       "npm test",
			ExternalId: "def-456",
			Number:     0,
			Progress: &deployer.JobStep_Complete{
				Complete: &deployer.StepComplete{
					Result:      deployer.Result_RESULT_SUCCEEDED,
					StartedAt:   startedAt,
					CompletedAt: completedAt,
					Log: &deployer.Log{
						Url:       "https://actions.githubusercontent.com/logs/1",
						Lines:     102,
						CreatedAt: completedAt,
					},
				},
			},
		}},
	}).Return(&empty.Empty{}, nil)
	s.ghTwirpClient.On("IsFeatureEnabledGlobally", mock.Anything, github.DisableStatusPostbacksFeatureFlag).Return(false)
	s.verifier.On("Verify", mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(true, nil)
	s.servicer.HandleJobStatus(res, req)
	s.Equal(http.StatusOK, res.Code)
}

func (s *ServiceSuite) TestStatusWithCompletedStatusUpdateMessageWithRunnerProperties() {
	startedAt := s.getProtoTime("2019-06-03T12:34:56Z")
	completedAt := s.getProtoTime("2019-06-03T12:35:56Z")
	expiresAt := s.getProtoTime("2019-07-03T12:35:56Z")

	reqBody := bytes.NewReader(fixture(s.T(), "job_status_update_postback_completed_with_runner_properties.json"))
	res := httptest.NewRecorder()
	req := s.getJobHTTPStatusRequest(http.MethodPatch, validWorkflowID, validJobID, reqBody)
	s.deployer.On("JobStatus", mock.Anything, &deployer.JobStatusRequest{
		WorkflowId:       validWorkflowID,
		JobId:            validJobID,
		DisplayName:      "Run tests",
		ExternalId:       "abc-123",
		Number:           5,
		RunnerType:       "SELF_HOSTED",
		RunnerProperties: "{\"machine_size\":2,\"azure_sku\":\"Standard_D2_v3\"}",
		Progress: &deployer.JobStatusRequest_Complete{
			Complete: &deployer.JobComplete{
				Result:      deployer.Result_RESULT_SUCCEEDED,
				StartedAt:   startedAt,
				CompletedAt: completedAt,
				SummaryUrl:  "https://codedev.ms/test/_apis/pipelines/plans/e3ef0826-5a8d-4b55-953b-b0e78abb4d17/summary?job=c92e7b95-6554-40c3-aff3-4e0ef3f36ffe",
				Log: &deployer.Log{
					Url:       "https://actions.githubusercontent.com/completed-logs/1",
					Lines:     101,
					CreatedAt: completedAt,
				},
			},
		},
		Artifacts: []*deployer.Artifact{{
			Name:      "foo.png",
			Size:      1024,
			Url:       "https://actions.githubusercontent.com/artifacts/screenshots/foo.png",
			CreatedAt: completedAt,
			ExpiresAt: expiresAt,
		}},
		Steps: []*deployer.JobStep{{
			Name:       "npm test",
			ExternalId: "def-456",
			Number:     0,
			Progress: &deployer.JobStep_Complete{
				Complete: &deployer.StepComplete{
					Result:      deployer.Result_RESULT_SUCCEEDED,
					StartedAt:   startedAt,
					CompletedAt: completedAt,
					Log: &deployer.Log{
						Url:       "https://actions.githubusercontent.com/logs/1",
						Lines:     102,
						CreatedAt: completedAt,
					},
				},
			},
		}},
	}).Return(&empty.Empty{}, nil)
	s.ghTwirpClient.On("IsFeatureEnabledGlobally", mock.Anything, github.DisableStatusPostbacksFeatureFlag).Return(false)
	s.verifier.On("Verify", mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(true, nil)
	s.servicer.HandleJobStatus(res, req)
	s.Equal(http.StatusOK, res.Code)
}

func (s *ServiceSuite) TestStatusWithCompletedStatusUpdateMessage_NullConclusion() {
	tests := []struct {
		name    string
		fixture string
	}{
		{
			name:    "null job conclusion",
			fixture: "job_status_update_postback_completed_null_conclusion.json",
		},
		{
			name:    "null step conclusion",
			fixture: "job_status_update_postback_completed_null_step_conclusion.json",
		},
	}

	for _, tc := range tests {
		s.Run(tc.name, func() {
			reqBody := bytes.NewReader(fixture(s.T(), tc.fixture))
			res := httptest.NewRecorder()
			req := s.getJobHTTPStatusRequest(http.MethodPatch, validWorkflowID, validJobID, reqBody)
			s.verifier.On("Verify", mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(true, nil)
			s.ghTwirpClient.On("IsFeatureEnabledGlobally", mock.Anything, github.DisableStatusPostbacksFeatureFlag).Return(false)
			s.servicer.HandleJobStatus(res, req)
			s.Equal(http.StatusBadRequest, res.Code)
		})
	}
}

func (s *ServiceSuite) TestStatusWithJobInProgressDelayed() {
	startedAt := s.getProtoTime("2019-06-03T12:34:56Z")
	expiresAt := s.getProtoTime("2019-06-03T12:36:56Z")

	reqBody := bytes.NewReader(fixture(s.T(), "job_status_update_postback_in_progress_delayed.json"))
	res := httptest.NewRecorder()
	req := s.getJobHTTPStatusRequest(http.MethodPatch, validWorkflowID, validJobID, reqBody)
	req.Header.Set("Authorization", s.getAuthorizationHeader())
	s.verifier.On("Verify", mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(true, nil)
	s.deployer.On("JobStatus", mock.Anything, &deployer.JobStatusRequest{
		WorkflowId:  validWorkflowID,
		JobId:       validJobID,
		DisplayName: "Run tests",
		ExternalId:  "abc-123",
		Number:      5,
		Progress: &deployer.JobStatusRequest_InProgress{
			InProgress: &deployer.JobInProgress{
				Status:    deployer.Status_STATUS_IN_PROGRESS,
				StartedAt: startedAt,
				LogStream: &deployer.LogStream{
					Url:       "https://actions.githubusercontent.com/streaming-logs/1",
					Token:     "ohdu2eez4Ho8uquohz7ugh2gieLeizei",
					ExpiresAt: expiresAt,
				},
			},
		},
		Artifacts: nil,
		Delayed:   true,
		Steps: []*deployer.JobStep{{
			Name:       "npm test",
			ExternalId: "def-456",
			Number:     0,
			Progress: &deployer.JobStep_InProgress{
				InProgress: &deployer.StepInProgress{
					Status:    deployer.Status_STATUS_IN_PROGRESS,
					StartedAt: startedAt,
				},
			},
		}, {
			Name:       "npm publish",
			ExternalId: "def-789",
			Number:     1,
			Progress: &deployer.JobStep_Queued{
				Queued: &deployer.StepQueued{},
			},
		}},
	}).Return(&empty.Empty{}, nil)
	s.ghTwirpClient.On("IsFeatureEnabledGlobally", mock.Anything, github.DisableStatusPostbacksFeatureFlag).Return(false)
	s.servicer.HandleJobStatus(res, req)
	s.Equal(http.StatusOK, res.Code)
}

func (s *ServiceSuite) TestStatusWithBadMessageBody() {
	res := httptest.NewRecorder()
	req := s.getJobHTTPStatusRequest(http.MethodPatch, validWorkflowID, validJobID, erroringReader{})
	s.servicer.HandleJobStatus(res, req)
	s.Equal(http.StatusInternalServerError, res.Code)
}

func (s *ServiceSuite) TestStatusWithDeployerTwirpFailure() {
	res := httptest.NewRecorder()
	req := s.getJobHTTPStatusRequest(http.MethodPatch, validWorkflowID, validJobID, nil)
	s.deployer.On("JobStatus", mock.Anything, mock.Anything).Return(nil, fmt.Errorf("deployer twirp failed"))
	s.ghTwirpClient.On("IsFeatureEnabledGlobally", mock.Anything, github.DisableStatusPostbacksFeatureFlag).Return(false)
	s.verifier.On("Verify", mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(true, nil)
	s.servicer.HandleJobStatus(res, req)
	s.Equal(http.StatusInternalServerError, res.Code)
}

func (s *ServiceSuite) TestStatusWithDeployerTwirpNotFound() {
	res := httptest.NewRecorder()
	req := s.getJobHTTPStatusRequest(http.MethodPatch, validWorkflowID, validJobID, nil)
	s.deployer.On("JobStatus", mock.Anything, mock.Anything).Return(nil, svcerr.NewNotFoundError("deployer twirp failed"))
	s.ghTwirpClient.On("IsFeatureEnabledGlobally", mock.Anything, github.DisableStatusPostbacksFeatureFlag).Return(false)
	s.verifier.On("Verify", mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(true, nil)
	s.servicer.HandleJobStatus(res, req)
	s.Equal(http.StatusNotFound, res.Code)
}

func (s *ServiceSuite) TestStatusWithInvalidSignature_ReturnsUnauthorized() {
	res := httptest.NewRecorder()
	req := s.getJobHTTPStatusRequest(http.MethodPatch, validWorkflowID, validJobID, nil)

	s.verifier.ExpectedCalls = []*mock.Call{} // Reset verify mock
	s.verifier.On("Verify", mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(false, nil)

	s.servicer.HandleJobStatus(res, req)
	s.Equal(http.StatusUnauthorized, res.Code)
}

func (s *ServiceSuite) TestStatusWithStatusUpdateVerificationError_ReturnsUnauthorized() {
	res := httptest.NewRecorder()
	req := s.getJobHTTPStatusRequest(http.MethodPatch, validWorkflowID, validJobID, nil)

	s.verifier.ExpectedCalls = []*mock.Call{} // Reset verify mock
	s.verifier.On("Verify", mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(true, fmt.Errorf("verifier failed"))

	s.servicer.HandleJobStatus(res, req)
	s.Equal(http.StatusBadRequest, res.Code)
}

func (s *ServiceSuite) TestRunStatus() {
	body := bytes.NewReader(fixture(s.T(), "run_status_postback.json"))
	res := httptest.NewRecorder()
	req := s.getRunHTTPStatusRequest(http.MethodPatch, validWorkflowID, body)
	req.Header.Set(azpcorrelation.VSSE2EIDHeaderName, "test-value")
	s.deployer.On("RunStatus", mock.Anything, &deployer.RunStatusRequest{
		WorkflowId: validWorkflowID,
		CompletedLog: &deployer.Log{
			Url: "https://actions.githubusercontent.com/completed-logs/1-log.zip",
		},
		Artifacts: []*deployer.Artifact{
			{
				Name:      "foo.png",
				Size:      1024,
				Url:       "https://actions.githubusercontent.com/artifacts/screenshots/foo.png",
				CreatedAt: s.getProtoTime(timestamp),
				ExpiresAt: s.getProtoTime(expiresTime),
			},
		},
		Progress: &deployer.RunStatusRequest_Complete{
			Complete: &deployer.RunComplete{
				Status:      deployer.RunStatus_COMPLETED,
				Conclusion:  deployer.RunConclusion_SUCCEEDED,
				CompletedAt: s.getProtoTime(completedTime),
				StartedAt:   s.getProtoTime(startedTime),
			},
		},
	}).Return(&empty.Empty{}, nil)
	s.ghTwirpClient.On("IsFeatureEnabledGlobally", mock.Anything, github.DisableStatusPostbacksFeatureFlag).Return(false)
	s.verifier.On("Verify", mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(true, nil)
	handlerForHandleRunStatus := middlewareForHeader(http.HandlerFunc(s.servicer.HandleRunStatus))
	handlerForHandleRunStatus.ServeHTTP(res, req)
	s.Equal(http.StatusOK, res.Code)
	s.Equal(res.Header().Get(azpcorrelation.VSSE2EIDHeaderName), "test-value")
	s.Empty(res.Body)
}

func (s *ServiceSuite) TestRunStatusCancelledRunNoTimes() {
	body := bytes.NewReader(fixture(s.T(), "run_status_cancelled_run_no_completed_at.json"))
	res := httptest.NewRecorder()
	req := s.getRunHTTPStatusRequest(http.MethodPatch, validWorkflowID, body)
	req.Header.Set(azpcorrelation.VSSE2EIDHeaderName, "test-value")
	s.deployer.On("RunStatus", mock.Anything, &deployer.RunStatusRequest{
		WorkflowId: validWorkflowID,
		CompletedLog: &deployer.Log{
			Url: "https://actions.githubusercontent.com/completed-logs/1-log.zip",
		},
		Artifacts: []*deployer.Artifact{
			{
				Name:      "foo.png",
				Size:      1024,
				Url:       "https://actions.githubusercontent.com/artifacts/screenshots/foo.png",
				CreatedAt: s.getProtoTime(timestamp),
				ExpiresAt: s.getProtoTime(expiresTime),
			},
		},
		Progress: &deployer.RunStatusRequest_Complete{
			Complete: &deployer.RunComplete{
				Status:      deployer.RunStatus_COMPLETED,
				Conclusion:  deployer.RunConclusion_CANCELED,
				CompletedAt: nil,
				StartedAt:   nil,
			},
		},
	}).Return(&empty.Empty{}, nil)
	s.ghTwirpClient.On("IsFeatureEnabledGlobally", mock.Anything, github.DisableStatusPostbacksFeatureFlag).Return(false)
	s.verifier.On("Verify", mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(true, nil)
	handlerForHandleRunStatus := middlewareForHeader(http.HandlerFunc(s.servicer.HandleRunStatus))
	handlerForHandleRunStatus.ServeHTTP(res, req)
	s.Equal(http.StatusOK, res.Code)
	s.Equal(res.Header().Get(azpcorrelation.VSSE2EIDHeaderName), "test-value")
	s.Empty(res.Body)
}

func (s *ServiceSuite) TestRunStatusWithEmptyLog() {
	body := bytes.NewReader(fixture(s.T(), "run_status_postback_empty_log.json"))
	res := httptest.NewRecorder()
	req := s.getRunHTTPStatusRequest(http.MethodPatch, validWorkflowID, body)
	s.deployer.On("RunStatus", mock.Anything, &deployer.RunStatusRequest{
		WorkflowId:   validWorkflowID,
		CompletedLog: nil,
		Artifacts: []*deployer.Artifact{
			{
				Name:      "foo.png",
				Size:      1024,
				Url:       "https://actions.githubusercontent.com/artifacts/screenshots/foo.png",
				CreatedAt: s.getProtoTime(timestamp),
				ExpiresAt: s.getProtoTime(expiresTime),
			},
		},
		Progress: &deployer.RunStatusRequest_Complete{
			Complete: &deployer.RunComplete{
				Status:      deployer.RunStatus_COMPLETED,
				Conclusion:  deployer.RunConclusion_SUCCEEDED,
				CompletedAt: s.getProtoTime(completedTime),
				StartedAt:   s.getProtoTime(startedTime),
			},
		},
	}).Return(&empty.Empty{}, nil)
	s.ghTwirpClient.On("IsFeatureEnabledGlobally", mock.Anything, github.DisableStatusPostbacksFeatureFlag).Return(false)
	s.verifier.On("Verify", mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(true, nil)
	s.servicer.HandleRunStatus(res, req)
	s.Equal(http.StatusOK, res.Code)
	s.Empty(res.Body)
}

func (s *ServiceSuite) TestRunStatusWithAnnotations() {
	body := bytes.NewReader(fixture(s.T(), "run_status_postback_with_annotations.json"))
	res := httptest.NewRecorder()
	req := s.getRunHTTPStatusRequest(http.MethodPatch, validWorkflowID, body)
	s.deployer.On("RunStatus", mock.Anything, &deployer.RunStatusRequest{
		WorkflowId: validWorkflowID,
		CompletedLog: &deployer.Log{
			Url: "https://actions.githubusercontent.com/completed-logs/1-log.zip",
		},
		Progress: &deployer.RunStatusRequest_Complete{
			Complete: &deployer.RunComplete{
				Status:      deployer.RunStatus_COMPLETED,
				Conclusion:  deployer.RunConclusion_SUCCEEDED,
				CompletedAt: s.getProtoTime(completedTime),
				StartedAt:   s.getProtoTime(startedTime),
			},
		},
		Annotations: []*deployer.Annotation{
			{
				AnnotationLevel: deployer.AnnotationLevel_LEVEL_WARNING,
				Message:         "annotation message",
				RawDetails:      "annotation raw details",
				Path:            ".github/workflows/ci.yaml",
				StartLine:       1,
				EndLine:         1,
				StartColumn:     1,
				EndColumn:       5,
			},
			{
				AnnotationLevel: deployer.AnnotationLevel_LEVEL_NOTICE,
				Message:         "annotation message",
				RawDetails:      "annotation raw details",
				Path:            ".github/workflows/cd.yaml",
				StartLine:       1,
				EndLine:         2,
			},
			{
				AnnotationLevel: deployer.AnnotationLevel_LEVEL_FAILURE,
				Message:         "missing path",
				RawDetails:      "annotation raw details",
				Path:            status.DefaultAnnotationPath,
				StartLine:       1,
				EndLine:         2,
			},
			{
				AnnotationLevel: deployer.AnnotationLevel_LEVEL_FAILURE,
				Message:         "missing lines",
				RawDetails:      "annotation raw details",
				Path:            ".github/workflows/cd.yaml",
				StartLine:       1,
				EndLine:         1,
			},
			{
				AnnotationLevel: deployer.AnnotationLevel_LEVEL_FAILURE,
				Message:         "zero lines",
				RawDetails:      "annotation raw details",
				Path:            ".github/workflows/cd.yaml",
				StartLine:       1,
				EndLine:         1,
			},
			{
				AnnotationLevel: deployer.AnnotationLevel_LEVEL_FAILURE,
				Message:         "multi-lines with columns",
				RawDetails:      "annotation raw details",
				Path:            ".github/workflows/cd.yaml",
				StartLine:       1,
				EndLine:         2,
				StartColumn:     0,
				EndColumn:       0,
			},
			{
				AnnotationLevel: deployer.AnnotationLevel_LEVEL_FAILURE,
				Message:         "bad start/end columns",
				RawDetails:      "annotation raw details",
				Path:            ".github/workflows/cd.yaml",
				StartLine:       1,
				EndLine:         1,
				StartColumn:     5,
				EndColumn:       5,
			},
			{
				AnnotationLevel: deployer.AnnotationLevel_LEVEL_FAILURE,
				Message:         "::errorr::Some error message that shows up in logs with a step number",
				RawDetails:      "annotation raw details",
				Path:            ".github",
				StartLine:       14,
				EndLine:         14,
				StartColumn:     1,
				EndColumn:       1,
				StepNumber:      3,
			},
		},
	}).Return(&empty.Empty{}, nil)
	s.ghTwirpClient.On("IsFeatureEnabledGlobally", mock.Anything, github.DisableStatusPostbacksFeatureFlag).Return(false)
	s.verifier.On("Verify", mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(true, nil)
	s.servicer.HandleRunStatus(res, req)
	s.Equal(http.StatusOK, res.Code)
	s.Empty(res.Body)
}

func (s *ServiceSuite) TestRunStatusWithConcurrency() {
	body := bytes.NewReader(fixture(s.T(), "run_status_postback_with_concurrency.json"))
	res := httptest.NewRecorder()
	req := s.getRunHTTPStatusRequest(http.MethodPatch, validWorkflowID, body)
	req.Header.Set(azpcorrelation.VSSE2EIDHeaderName, "test-value")
	s.deployer.On("RunStatus", mock.Anything, &deployer.RunStatusRequest{
		WorkflowId: validWorkflowID,
		Progress: &deployer.RunStatusRequest_NotStarted{
			NotStarted: &deployer.RunNotStarted{
				Status: deployer.RunStatus_PENDING,
			},
		},
		Concurrency: &deployer.Concurrency{
			Group: "testGroup",
		},
	}).Return(&empty.Empty{}, nil)
	s.ghTwirpClient.On("IsFeatureEnabledGlobally", mock.Anything, github.DisableStatusPostbacksFeatureFlag).Return(false)
	s.verifier.On("Verify", mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(true, nil)
	handlerForHandleRunStatus := middlewareForHeader(http.HandlerFunc(s.servicer.HandleRunStatus))
	handlerForHandleRunStatus.ServeHTTP(res, req)
	s.Equal(http.StatusOK, res.Code)
	s.Equal(res.Header().Get(azpcorrelation.VSSE2EIDHeaderName), "test-value")
	s.Empty(res.Body)
}

func (s *ServiceSuite) TestVerifySignature_CalledWithCorrectParams() {
	res := httptest.NewRecorder()
	req := s.getJobHTTPStatusRequest(http.MethodPatch, validWorkflowID, validJobID, nil)

	timestampTime, err := time.Parse(time.RFC3339, timestamp)
	s.NoError(err)

	reqBody, err := io.ReadAll(bytes.NewReader(fixture(s.T(), "job_status_update_postback_in_progress.json")))
	s.NoError(err)

	var sigBody strings.Builder
	sigBody.WriteString("https://launch-receiver-test.githubapp.com/actions/build/c6138ef3-98fe-4a76-bd86-7c6045a3c141/jobs/fa5aabba-8868-4de2-aa56-0f0320489fe9?timestamp=2019-07-03T14%3A33%3A44Z")
	sigBody.WriteString("\n")
	sigBody.Write(reqBody)

	s.verifier.ExpectedCalls = nil // Reset verify mock
	s.verifier.On("Verify",
		validWorkflowID,
		timestampTime,
		[]byte(sigBody.String()),
		rawSignature,
	).Return(false, nil)

	s.servicer.HandleJobStatus(res, req)
	s.Equal(http.StatusUnauthorized, res.Code)
}

func (s *ServiceSuite) TestGateStatusWithDeployerTwirpFailure() {
	res := httptest.NewRecorder()
	req := s.getGateHTTPStatusRequest(http.MethodPatch, validWorkflowID, "testGateID", nil)
	s.deployer = &deployer.MockLaunchStatusService{}
	s.deployer.On("GateStatus", mock.Anything, mock.Anything).Return(nil, fmt.Errorf("deployer twirp failed"))
	s.servicer.Deployer = s.deployer
	s.ghTwirpClient.On("IsFeatureEnabledGlobally", mock.Anything, github.DisableStatusPostbacksFeatureFlag).Return(false)
	s.verifier.On("Verify", mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(true, nil)
	s.servicer.HandleGateStatus(res, req)
	s.Equal(http.StatusInternalServerError, res.Code)
}

func (s *ServiceSuite) TestGateStatusWithNotFoundGraphQlError() {
	res := httptest.NewRecorder()
	req := s.getGateHTTPStatusRequest(http.MethodPatch, validWorkflowID, "testGateID", nil)
	s.deployer = &deployer.MockLaunchStatusService{}
	s.deployer.On("GateStatus", mock.Anything, mock.Anything).Return(nil, svcerr.NewNotFoundError("Not found"))
	s.servicer.Deployer = s.deployer
	s.ghTwirpClient.On("IsFeatureEnabledGlobally", mock.Anything, github.DisableStatusPostbacksFeatureFlag).Return(false)
	s.verifier.On("Verify", mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(true, nil)
	s.servicer.HandleGateStatus(res, req)
	s.Equal(http.StatusNotFound, res.Code)
}

func (s *ServiceSuite) getProtoTime(input string) *tspb.Timestamp {
	out, err := time.Parse(time.RFC3339Nano, input)
	s.NoError(err)
	outProto := timestamppb.New(out)
	s.NoError(err)
	return outProto
}

type erroringReader struct{}

func (erroringReader) Read(p []byte) (n int, err error) {
	return 0, errors.New("erroringReader returns an error when read")
}

func (s *ServiceSuite) getJobHTTPStatusRequest(method, workflowID, jobID string, body io.Reader) *http.Request {
	if body == nil {
		body = bytes.NewReader(fixture(s.T(), "job_status_update_postback_in_progress.json"))
	}
	rctx := chi.NewRouteContext()
	rctx.URLParams.Add("workflowID", workflowID)
	rctx.URLParams.Add("jobID", jobID)
	url := fmt.Sprintf("/actions/build/%s/jobs/%s?timestamp=%s", workflowID, jobID, url.QueryEscape(timestamp))
	req := httptest.NewRequest(method, url, body)
	req.Header.Set("Authorization", s.getAuthorizationHeader())
	ctx := measurehttp.WithThresholdLogging(req.Context())
	req = req.WithContext(ctx)
	return req.WithContext(context.WithValue(req.Context(), chi.RouteCtxKey, rctx))
}

func (s *ServiceSuite) getRunHTTPStatusRequest(method, workflowID string, body io.Reader) *http.Request {
	rctx := chi.NewRouteContext()
	rctx.URLParams.Add("workflowID", workflowID)
	url := fmt.Sprintf("/actions/build/%s?timestamp=%s", workflowID, url.QueryEscape(timestamp))
	req := httptest.NewRequest(method, url, body)
	req.Header.Set("Authorization", s.getAuthorizationHeader())
	ctx := measurehttp.WithThresholdLogging(req.Context())
	req = req.WithContext(ctx)
	return req.WithContext(context.WithValue(req.Context(), chi.RouteCtxKey, rctx))
}

func (s *ServiceSuite) getGateHTTPStatusRequest(method, workflowID, gateID string, body io.Reader) *http.Request {
	if body == nil {
		body = bytes.NewReader(fixture(s.T(), "gate_status_postback.json"))
	}
	rctx := chi.NewRouteContext()
	rctx.URLParams.Add("workflowID", workflowID)
	rctx.URLParams.Add("gateID", gateID)
	url := fmt.Sprintf("/actions/build/%s/gates/%s?timestamp=%s", workflowID, gateID, url.QueryEscape(timestamp))
	req := httptest.NewRequest(method, url, body)
	req.Header.Set("Authorization", s.getAuthorizationHeader())
	ctx := measurehttp.WithThresholdLogging(req.Context())
	req = req.WithContext(ctx)
	return req.WithContext(context.WithValue(req.Context(), chi.RouteCtxKey, rctx))
}

func (s *ServiceSuite) getAuthorizationHeader() string {
	return fmt.Sprintf("HMAC-SHA512 Signature=%s", base64.StdEncoding.EncodeToString(rawSignature))
}
