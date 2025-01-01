package resolveactions

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
	"strings"
	"testing"
	"time"

	"github.com/facebookgo/clock"
	"github.com/go-chi/chi"
	"github.com/golang/protobuf/ptypes/empty"
	tspb "github.com/golang/protobuf/ptypes/timestamp"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/suite"
	"google.golang.org/protobuf/types/known/timestamppb"

	"github.com/github/launch/pkg/mu"

	"github.com/github/launch/observability"
	"github.com/github/launch/observability/azpcorrelation"
	"github.com/github/launch/observability/ctxstash"
	"github.com/github/launch/observability/measurehttp"
	"github.com/github/launch/services/auth/hkdf"
	"github.com/github/launch/services/pb/deploy"
)

const (
	validWorkflowID    = "c6138ef3-98fe-4a76-bd86-7c6045a3c141"
	validJobID         = "fa5aabba-8868-4de2-aa56-0f0320489fe9"
	timestamp          = "2019-07-03T14:33:44Z"
	exampleRequestBody = `{"actions":[{"action":"actions/checkout","version":"v2"}]}`
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

type ServiceSuite struct {
	suite.Suite
	servicer *Servicer
	deployer *deploy.MockLaunchDeploymentService
	verifier *hkdf.MockVerifier
	clock    clock.Clock
	server   *httptest.Server
}

func TestServiceSuite(t *testing.T) {
	suite.Run(t, new(ServiceSuite))
}

func (s *ServiceSuite) SetupTest() {
	s.deployer = &deploy.MockLaunchDeploymentService{}
	s.verifier = &hkdf.MockVerifier{}
	s.verifier.On("Verify", mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(true, nil)
	s.clock = clock.New()
	s.servicer = &Servicer{
		Obs:         observability.NewNullObservability(),
		Verifier:    s.verifier,
		Deployer:    s.deployer,
		ReceiverURL: "https://launch-receiver-test.githubapp.com",
	}

	r := chi.NewRouter()
	mu.RouteService(r, s.servicer, func(h http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			ctx := measurehttp.WithThresholdLogging(r.Context())
			h.ServeHTTP(w, r.WithContext(ctx))
		})
	})

	srv := httptest.NewServer(middlewareForHeader(r))
	s.server = srv
}

func (s *ServiceSuite) TearDownTest() {
	s.server.Close()
}

func (s *ServiceSuite) TestMissingSignature() {
	req := s.getResolveActionsHTTPRequest(http.MethodPost, validWorkflowID, validJobID, exampleRequestBody)
	req.Header.Del("Authorization")
	s.deployer.On("ResolveActions", mock.Anything, mock.Anything).Return(&empty.Empty{}, nil)
	res, err := http.DefaultClient.Do(req)
	s.Require().NoError(err)
	s.Equal(http.StatusBadRequest, res.StatusCode)
}

func (s *ServiceSuite) TestInvalidSignatureEncoding() {
	req := s.getResolveActionsHTTPRequest(http.MethodPost, validWorkflowID, validJobID, exampleRequestBody)
	req.Header.Set("Authorization", "😱")
	s.deployer.On("ResolveActions", mock.Anything, mock.Anything).Return(&empty.Empty{}, nil)
	res, err := http.DefaultClient.Do(req)
	s.Require().NoError(err)
	s.Equal(http.StatusBadRequest, res.StatusCode)
}

func (s *ServiceSuite) TestInvalidRequestBody() {
	req := s.getResolveActionsHTTPRequest(http.MethodPost, validWorkflowID, validJobID, "{a}")
	res, err := http.DefaultClient.Do(req)
	s.Require().NoError(err)
	s.Equal(http.StatusUnprocessableEntity, res.StatusCode)
}

func (s *ServiceSuite) TestCorrelationHeaders() {
	req := s.getResolveActionsHTTPRequest(http.MethodPost, validWorkflowID, validJobID, exampleRequestBody)
	req.Header.Set("Authorization", "TmV3UGhvbmVXaG9EaXM=")
	req.Header.Set(azpcorrelation.VSSE2EIDHeaderName, "test-value")
	s.verifier.On("Verify", mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(true, nil)
	res, err := http.DefaultClient.Do(req)
	s.Require().NoError(err)
	s.Assert().Equal(http.StatusBadRequest, res.StatusCode)
	s.Assert().Equal(res.Header.Get(azpcorrelation.VSSE2EIDHeaderName), "test-value")
}

func (s *ServiceSuite) TestResolveActionsReturnsError() {
	req := s.getResolveActionsHTTPRequest(http.MethodPost, validWorkflowID, validJobID, exampleRequestBody)
	s.deployer.On("ResolveActions", mock.Anything, &deploy.ResolveActionsRequest{
		WorkflowId: validWorkflowID,
		JobId:      validJobID,
		Actions: []*deploy.ActionReference{
			{
				Name:    "actions/checkout",
				Version: "v2",
			},
		},
	}).Return(&deploy.ResolveActionsResponse{
		Errors: []*deploy.ResolvedActionError{
			{
				Action: &deploy.ActionReference{
					Name:    "actions/checkout",
					Version: "v2",
				},
				Message: "Could not find action",
			},
		},
	}, nil)
	res, err := http.DefaultClient.Do(req)
	s.Require().NoError(err)
	s.Equal(http.StatusUnprocessableEntity, res.StatusCode)
	resBody, err := io.ReadAll(res.Body)
	s.Require().NoError(err)
	s.JSONEq(`{
	"actions": {},
  "errors": {
   "actions/checkout@v2": {
      "message": "Could not find action"
      }
    }
  }`, string(resBody))

	s.deployer.AssertExpectations(s.T())
}

type testRateLimitedError struct {
	error
}

func (r *testRateLimitedError) RateLimited() bool {
	return true
}

func (s *ServiceSuite) TestResolveActionsReturnsResourceExhaustedError() {
	req := s.getResolveActionsHTTPRequest(http.MethodPost, validWorkflowID, validJobID, exampleRequestBody)
	s.deployer.On("ResolveActions", mock.Anything, &deploy.ResolveActionsRequest{
		WorkflowId: validWorkflowID,
		JobId:      validJobID,
		Actions: []*deploy.ActionReference{
			{
				Name:    "actions/checkout",
				Version: "v2",
			},
		},
	}).Return(nil, &testRateLimitedError{errors.New("rate limited")})

	res, err := http.DefaultClient.Do(req)
	s.Require().NoError(err)
	s.Equal(http.StatusTooManyRequests, res.StatusCode)

	s.deployer.AssertExpectations(s.T())
}

func (s *ServiceSuite) TestResolveActionsSuccessfully() {
	expiresAt := s.getProtoTime("2019-06-03T12:36:56Z")

	req := s.getResolveActionsHTTPRequest(http.MethodPost, validWorkflowID, validJobID, exampleRequestBody)
	s.deployer.On("ResolveActions", mock.Anything, &deploy.ResolveActionsRequest{
		WorkflowId: validWorkflowID,
		JobId:      validJobID,
		Actions: []*deploy.ActionReference{
			{
				Name:    "actions/checkout",
				Version: "v2",
			},
		},
	}).Return(&deploy.ResolveActionsResponse{
		Actions: []*deploy.ResolvedAction{
			{
				Action: &deploy.ActionReference{
					Name:    "actions/checkout",
					Version: "v2",
				},
				ResolvedName: "github-actions/checkout",
				ResolvedSha:  "2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3",
				TarUrl:       "https://www.example.com/github-actions/checkout.tar.gz",
				ZipUrl:       "https://www.example.com/github-actions/checkout.zip",
				Authentication: &deploy.ResolvedActionAuthentication{
					Token:     "asdfasdfasd",
					ExpiresAt: expiresAt,
				},
				PackageDetails: nil,
			},
		},
	}, nil)
	res, err := http.DefaultClient.Do(req)
	s.Require().NoError(err)
	s.Equal(http.StatusOK, res.StatusCode)
	resBody, err := io.ReadAll(res.Body)
	s.Require().NoError(err)
	s.JSONEq(`{
  "actions": {
   "actions/checkout@v2": {
      "name": "actions/checkout",
      "resolved_name": "github-actions/checkout",
      "version": "v2",
      "resolved_sha": "2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3",
      "tar_url": "https://www.example.com/github-actions/checkout.tar.gz",
      "zip_url": "https://www.example.com/github-actions/checkout.zip",
      "authentication": {
        "token": "asdfasdfasd",
        "expires_at": "2019-06-03T12:36:56Z"
      },
      "package_details": null
    }
  },
	"errors": {}
}`, string(resBody))

	s.deployer.AssertExpectations(s.T())
}

func (s *ServiceSuite) TestResolveActionsSuccessfullyOmitsAuthenticationWhenNil() {

	req := s.getResolveActionsHTTPRequest(http.MethodPost, validWorkflowID, validJobID, exampleRequestBody)
	s.deployer.On("ResolveActions", mock.Anything, &deploy.ResolveActionsRequest{
		WorkflowId: validWorkflowID,
		JobId:      validJobID,
		Actions: []*deploy.ActionReference{
			{
				Name:    "actions/checkout",
				Version: "v2",
			},
		},
	}).Return(&deploy.ResolveActionsResponse{
		Actions: []*deploy.ResolvedAction{
			{
				Action: &deploy.ActionReference{
					Name:    "actions/checkout",
					Version: "v2",
				},
				ResolvedName:   "github-actions/checkout",
				ResolvedSha:    "2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3",
				TarUrl:         "https://www.example.com/github-actions/checkout.tar.gz",
				ZipUrl:         "https://www.example.com/github-actions/checkout.zip",
				Authentication: nil,
				PackageDetails: nil,
			},
		},
	}, nil)
	res, err := http.DefaultClient.Do(req)
	s.Require().NoError(err)
	s.Equal(http.StatusOK, res.StatusCode)
	resBody, err := io.ReadAll(res.Body)
	s.Require().NoError(err)
	s.JSONEq(`{
  "actions": {
   "actions/checkout@v2": {
      "name": "actions/checkout",
      "resolved_name": "github-actions/checkout",
      "version": "v2",
      "resolved_sha": "2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3",
      "tar_url": "https://www.example.com/github-actions/checkout.tar.gz",
      "zip_url": "https://www.example.com/github-actions/checkout.zip",
      "authentication": null,
      "package_details": null
    }
  },
	"errors": {}
}`, string(resBody))

	s.deployer.AssertExpectations(s.T())
}

func (s *ServiceSuite) TestResolveImmutableActionsSuccessfully() {

	req := s.getResolveActionsHTTPRequest(http.MethodPost, validWorkflowID, validJobID, exampleRequestBody)
	s.deployer.On("ResolveActions", mock.Anything, &deploy.ResolveActionsRequest{
		WorkflowId: validWorkflowID,
		JobId:      validJobID,
		Actions: []*deploy.ActionReference{
			{
				Name:    "actions/checkout",
				Version: "v2",
			},
		},
	}).Return(&deploy.ResolveActionsResponse{
		Actions: []*deploy.ResolvedAction{
			{
				Action: &deploy.ActionReference{
					Name:    "actions/checkout",
					Version: "v2",
				},
				ResolvedName:   "github-actions/checkout",
				ResolvedSha:    "2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3",
				TarUrl:         "https://www.example.com/github-actions/checkout.tar.gz",
				ZipUrl:         "https://www.example.com/github-actions/checkout.zip",
				Authentication: nil,
				PackageDetails: &deploy.ResolvedActionPackageDetails{
					Version:        "1.0.0",
					ManifestDigest: "sha256:1234",
				},
			},
		},
	}, nil)
	res, err := http.DefaultClient.Do(req)
	s.Require().NoError(err)
	s.Equal(http.StatusOK, res.StatusCode)
	resBody, err := io.ReadAll(res.Body)
	s.Require().NoError(err)
	s.JSONEq(`{
  "actions": {
   "actions/checkout@v2": {
      "name": "actions/checkout",
      "resolved_name": "github-actions/checkout",
      "version": "v2",
      "resolved_sha": "2ff2fbdea48a8f5da77a31e7dd5ecb46c017ffc3",
      "tar_url": "https://www.example.com/github-actions/checkout.tar.gz",
      "zip_url": "https://www.example.com/github-actions/checkout.zip",
      "authentication": null,
      "package_details": {
        "version": "1.0.0",
        "manifest_digest": "sha256:1234"
      }
    }
  },
	"errors": {}
}`, string(resBody))

	s.deployer.AssertExpectations(s.T())
}

func (s *ServiceSuite) TestVerifySignature_CalledWithCorrectParams() {

	req := s.getResolveActionsHTTPRequest(http.MethodPost, validWorkflowID, validJobID, exampleRequestBody)
	s.deployer.On("ResolveActions", mock.Anything, mock.Anything).Return(&empty.Empty{}, nil)

	timestampTime, err := time.Parse(time.RFC3339, timestamp)
	s.NoError(err)

	var sigBody strings.Builder
	sigBody.WriteString("https://launch-receiver-test.githubapp.com/actions/build/c6138ef3-98fe-4a76-bd86-7c6045a3c141/jobs/fa5aabba-8868-4de2-aa56-0f0320489fe9/resolve/actions?timestamp=2019-07-03T14%3A33%3A44Z")
	sigBody.WriteString("\n")
	sigBody.Write([]byte(exampleRequestBody))

	s.verifier.ExpectedCalls = nil // Reset verify mock
	s.verifier.On("Verify",
		validWorkflowID,
		timestampTime,
		[]byte(sigBody.String()),
		rawSignature,
	).Return(false, nil)

	res, err := http.DefaultClient.Do(req)
	s.Require().NoError(err)
	s.Equal(http.StatusUnauthorized, res.StatusCode)

	s.verifier.AssertExpectations(s.T())
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

func (s *ServiceSuite) getResolveActionsHTTPRequest(method, workflowID, jobID string, data string) *http.Request {
	body := bytes.NewBufferString(data)
	rctx := chi.NewRouteContext()
	rctx.URLParams.Add("workflowID", workflowID)
	rctx.URLParams.Add("jobID", jobID)
	url := fmt.Sprintf("%s/actions/build/%s/jobs/%s/resolve/actions?timestamp=%s", s.server.URL, workflowID, jobID, url.QueryEscape(timestamp))
	req, err := http.NewRequest(method, url, body)
	s.Require().NoError(err)
	req.Header.Set("Authorization", s.getAuthorizationHeader())
	ctx := measurehttp.WithThresholdLogging(req.Context())
	req = req.WithContext(ctx)
	return req.WithContext(context.WithValue(req.Context(), chi.RouteCtxKey, rctx))
}

func (s *ServiceSuite) getAuthorizationHeader() string {
	return fmt.Sprintf("HMAC-SHA512 Signature=%s", base64.StdEncoding.EncodeToString(rawSignature))
}
