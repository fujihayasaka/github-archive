package refreshjobtoken_test

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"net/url"
	"testing"
	"time"

	"github.com/go-chi/chi"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/suite"
	"google.golang.org/protobuf/types/known/timestamppb"

	"github.com/github/launch/observability/logger"
	"github.com/github/launch/observability/measurehttp"
	"github.com/github/launch/observability/statter"
	"github.com/github/launch/services/auth/hkdf"
	svcerr "github.com/github/launch/services/errors"
	tokenService "github.com/github/launch/services/pb/deploy/token"
	"github.com/github/launch/services/receiver/refreshjobtoken"
	"github.com/github/launch/types"
)

const (
	validWorkflowID = "c6138ef3-98fe-4a76-bd86-7c6045a3c141"
	validJobID      = "fa5aabba-8868-4de2-aa56-0f0320489fe9"
	timestamp       = "2019-07-03T14:33:44Z"
)

var rawSignature = []byte("NewPhoneWhoDis")

type ServiceSuite struct {
	suite.Suite
	verifier     *hkdf.MockVerifier
	tokenService *tokenService.MockLaunchTokenService
	servicer     *refreshjobtoken.Servicer
}

func TestServiceSuite(t *testing.T) {
	suite.Run(t, new(ServiceSuite))
}

func getGloballyEnabledFeature(ctx context.Context, repoID string) bool {
	return true
}

func getGloballyDisabledFeature(ctx context.Context, repoID string) bool {
	return false
}

func getRepoEnabledFeature(ctx context.Context, repoID string, feature types.GlobalID) bool {
	return true
}

func getRepoDisabledFeature(ctx context.Context, repoID string, feature types.GlobalID) bool {
	return false
}

func (s *ServiceSuite) SetupTest() {
	s.tokenService = &tokenService.MockLaunchTokenService{}
	s.verifier = &hkdf.MockVerifier{}

	s.servicer = &refreshjobtoken.Servicer{
		Log:          logger.NullLogger(),
		Stats:        statter.NullStatter(),
		Verifier:     s.verifier,
		TokenService: s.tokenService,
	}
}

func (s *ServiceSuite) TearDownTest() {
	s.verifier.AssertExpectations(s.T())
	s.tokenService.AssertExpectations(s.T())
}

func (s *ServiceSuite) getHandleTokenRefreshRequest(workflowID, jobID string) *http.Request {
	body := bytes.NewReader([]byte("{}"))

	rctx := chi.NewRouteContext()
	rctx.URLParams.Add("workflowID", workflowID)
	rctx.URLParams.Add("jobID", jobID)

	url := fmt.Sprintf("/actions/build/%s/jobs/%s/refresh_job_tokens?timestamp=%s", workflowID, jobID, url.QueryEscape(timestamp))
	req := httptest.NewRequest(http.MethodPost, url, body)
	req.Header.Set("Authorization", s.getAuthorizationHeader())

	ctx := measurehttp.WithThresholdLogging(req.Context())
	req = req.WithContext(ctx)

	fmt.Printf("url url %+v\n", url)

	return req.WithContext(context.WithValue(req.Context(), chi.RouteCtxKey, rctx))
}

func (s *ServiceSuite) getAuthorizationHeader() string {
	return fmt.Sprintf("HMAC-SHA512 Signature=%s", base64.StdEncoding.EncodeToString(rawSignature))
}

func (s *ServiceSuite) TestGetToken_MissingSignature() {
	res := httptest.NewRecorder()
	req := s.getHandleTokenRefreshRequest(validWorkflowID, validJobID)
	req.Header.Del("Authorization")
	s.verifier.ExpectedCalls = []*mock.Call{}

	s.servicer.HandleTokenRefresh(res, req)
	s.Equal(http.StatusBadRequest, res.Code)
}

func (s *ServiceSuite) TestGetToken_InvalidSignatureEncoding() {
	res := httptest.NewRecorder()
	req := s.getHandleTokenRefreshRequest(validWorkflowID, validJobID)
	req.Header.Set("Authorization", "😱")

	s.servicer.HandleTokenRefresh(res, req)
	s.Equal(http.StatusBadRequest, res.Code)
}

func (s *ServiceSuite) TestRefreshToken_Success() {
	res := httptest.NewRecorder()
	req := s.getHandleTokenRefreshRequest(validWorkflowID, validJobID)
	req.Header.Set("Authorization", "HMAC-SHA512 Signature=TmV3UGhvbmVXaG9EaXM=")

	now := time.Now().UTC()
	pbNow := timestamppb.New(now)

	tok := tokenService.RefreshTokenResponse{
		Token:     "abc123",
		ExpiresAt: pbNow,
	}
	s.verifier.On("Verify", validWorkflowID, mock.Anything, mock.Anything, mock.Anything).Return(true, nil)
	s.tokenService.On("RefreshToken", mock.Anything, mock.MatchedBy(func(refReq *tokenService.RefreshTokenRequest) bool {
		return (refReq.WorkflowId == validWorkflowID)
	})).Return(&tok, nil)

	s.servicer.HandleTokenRefresh(res, req)

	var tokenRes refreshjobtoken.ServiceResponse
	err := json.NewDecoder(res.Body).Decode(&tokenRes)
	s.NoError(err)

	s.Equal(http.StatusOK, res.Code)
	s.Equal(now.Format(time.RFC3339Nano), tokenRes.ExpiresAt)
	s.Equal(tok.Token, tokenRes.Token)
}

func (s *ServiceSuite) TestRefreshToken_ErrorInvalidToken() {
	res := httptest.NewRecorder()
	req := s.getHandleTokenRefreshRequest(validWorkflowID, validJobID)
	req.Header.Set("Authorization", "HMAC-SHA512 Signature=TmV3UGhvbmVXaG9EaXM=")

	s.verifier.On("Verify", validWorkflowID, mock.Anything, mock.Anything, mock.Anything).Return(true, nil)
	s.tokenService.On("RefreshToken", mock.Anything, mock.MatchedBy(func(refReq *tokenService.RefreshTokenRequest) bool {
		return (refReq.WorkflowId == validWorkflowID)
	})).Return(nil, svcerr.NewInternalError("Could not refresh token: invalid installation token"))

	s.servicer.HandleTokenRefresh(res, req)

	s.Equal(http.StatusUnauthorized, res.Code)
}
